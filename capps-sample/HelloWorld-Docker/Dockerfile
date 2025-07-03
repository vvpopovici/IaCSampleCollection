# docker build ./ -t helloworld -f Dockerfile-helloworld
# docker run -p 5000:5000 --rm -it helloworld
# docker run -p 5001:5001 -e PORT=5001 --rm -it helloworld

ARG IMAGE=python:3.9-slim-buster
# ARG IMAGE=mcr.microsoft.com/azure-functions/python:4-python3.9
FROM $IMAGE

ENV PORT=5000

WORKDIR /
# The "<link rel=..." part is required to avoid requests to /favicon.ico
# RUN echo '<link rel="shortcut icon" href="#" /> Hello world!' > /index.html
RUN echo 'Hello world!' > /index.html

HEALTHCHECK --interval=30s --timeout=30s --start-period=30s --retries=3 CMD python -c "import socket; socket.setdefaulttimeout(5); socket.create_connection((f'127.0.0.1', ${PORT}))"

# CMD python -m http.server ${PORT}

COPY ./startup.py /
COPY ./favicon.ico /
CMD [ "/startup.py" ]

