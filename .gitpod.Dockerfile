# setup.py requires Python >= 3.14, but no gitpod/workspace-python-3.14 image
# exists. These images manage interpreters via pyenv (see gitpod-io/workspace-images,
# chunks/lang-python/Dockerfile), so install 3.14 on top of the newest available one.
FROM gitpod/workspace-python-3.13

USER gitpod
RUN pyenv install 3.14.2 && pyenv global 3.14.2

COPY requirements_generate.txt requirements_generate.txt
RUN pip install -r requirements_generate.txt
