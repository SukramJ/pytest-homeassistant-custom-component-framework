# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is **not** a hand-written library. It is a *generator*: `generate_phacc/` clones
home-assistant/core, extracts the test helpers/fixtures from its `tests/` directory,
rewrites their imports, and emits the installable package
`src/pytest_homeassistant_custom_component/`. That emitted package is committed to git
and published to PyPI as `pytest-homeassistant-custom-component-framework`.

**The generated package is not the source.** Never hand-edit anything under
`src/pytest_homeassistant_custom_component/` — regenerate it instead. Changes to
extraction behaviour belong in `generate_phacc/generate_phacc.py` or
`generate_phacc/const.py`. PRs are expected not to contain changes to the generated
files; CI regenerates them.

Python >= 3.14 (`setup.py`), matching the HA core version the package tracks.

## Commands

```sh
# one-time setup (both steps needed: the generator imports the installed package
# to read its __version__ at the end of a run)
pip install -r requirements_generate.txt
pip install -e .

# regenerate the package (skips work if `ha_version` already matches the newest
# home-assistant/core tag; --regen forces it)
export PYTHONPATH=$PYTHONPATH:$(pwd)
python generate_phacc/generate_phacc.py [--regen]

# tests (asyncio_mode = auto is set in setup.cfg; no marker needed)
pytest
pytest tests/test_sensor.py::test_sensor
pytest --snapshot-update          # syrupy snapshots in tests/snapshots/
```

The generator clones home-assistant/core into `tmp_dir/` and **reuses that clone if the
directory already exists** — delete `tmp_dir/` to pick up newly published upstream tags.

## Generation pipeline (`generate_phacc/`)

`generate_phacc.py` is the whole pipeline; `const.py` is its configuration, `ha.py`
handles the clone and version selection.

1. `ha.prepare_homeassistant()` clones core, parses every git tag through `HAVersion`
   (which understands the `2026.9.0b0` beta suffix) and checks out the highest one.
   Beta releases are included on purpose — the package tracks them daily.
2. `PACKAGE_DIR` and `requirements_test.txt` are deleted and rebuilt from scratch on
   every run, so the run is not incremental.
3. Files listed in `const.files` are copied from core's `tests/`; `from tests.` is
   rewritten to a relative import whose dot count is derived from the file's depth.
   Add new extracted files to `const.files` — anything needing a directory that does
   not yet exist also needs an `os.makedirs` in `process_files()`.
4. `tests/conftest.py` becomes `plugins.py`. This is the pytest plugin registered via
   the `pytest11` entry point in `setup.py`, which is what makes `hass` and the other
   HA fixtures available to consumers without any conftest wiring.
5. Two source patches are applied by **line-offset arithmetic against anchor lines**
   (`assert len(...) == 1` guards them), so they break loudly when upstream moves code:
   - `common.py`: `get_fixture_path` is rewritten to walk `traceback.extract_stack()`
     back to the *calling* test file, so `load_fixture` resolves fixtures relative to
     the consumer's test rather than to the installed package.
   - `components/diagnostics/__init__.py`: `tests.typing` →
     `pytest_homeassistant_custom_component.typing`.
6. `homeassistant/const.py` is truncated to the version constants only — this is what
   makes `pytest_homeassistant_custom_component.const.__version__` report the HA core
   version.
7. Core's `requirements_test.txt` is split: anything matching `types-*` or listed in
   `const.requirements_remove` goes to `requirements_dev.txt`, the rest stays in
   `requirements_test.txt` (which `setup.py` reads to build `install_requires`).
   Pinned `sqlalchemy`, `paho-mqtt`, `numpy` and `aiohasupervisor` lines are looked up
   in core's `requirements_all.txt` and appended, plus `homeassistant==<tag>`.
   Both files are *generated* — do not bump pins in them by hand. `requirements_dev.txt`
   in particular is only ever written, never read: nothing installs it, and hand-edits
   are silently reverted by the next `--regen`. `requirements_generate.txt` (click,
   GitPython) is the only hand-maintained requirements file.
8. `ha_version` and the badge line in `README.md` (hardcoded as `data[2]`) are updated.

## Version files

- `ha_version` — the home-assistant/core tag the committed package was generated from.
  The generator compares against it to decide whether there is anything to do.
- `version` — the package's own semver, bumped by CI. Minor = a change in extraction
  logic, patch = an automatic HA-version-only update.
- Both are read as raw file contents (no trailing newline); `setup.py` reads `version`.

## Packaging

`setup.py` reads `version`, `requirements_test.txt` and `README.md` with a plain
`open()` at build time. `python -m build` builds the wheel *from the sdist*, so those
files have to be inside the sdist — that is what `MANIFEST.in` is for. Drop an entry
from it and the wheel build fails with `FileNotFoundError` while `pip install -e .`
keeps working, so the breakage only shows up in the release workflows.

## Tests

`tests/` and `custom_components/simple_integration/` exist to smoke-test the *generated*
package the same way a downstream consumer would use it — config flow, sensor,
diagnostics snapshot, and the patched `load_fixture` path resolution. They are not tests
of the generator. `tests/conftest.py` shows the two things consumers must do themselves:
register `HomeAssistantSnapshotExtension` on the `snapshot` fixture, and depend on
`enable_custom_integrations`.

## CI

- `pytest.yml` (push/PR/daily) regenerates with `--regen` and then runs the tests —
  so a generator change is validated against the newest HA release automatically.
- `automatic_generation.yml` (daily 05:00 UTC) regenerates without `--regen`, and only
  if `ha_version` changed does it test, bump the patch version, commit "Bump version",
  tag, release and publish to PyPI. This is why the git history is almost entirely
  "Bump version" commits.
- `generate_package.yml` runs `--regen` and opens a PR instead of committing.
- `make_release.yml` / `publish.yml` are manual (`workflow_dispatch`).
