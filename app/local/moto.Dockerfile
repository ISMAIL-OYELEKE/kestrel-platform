# Local AWS emulator (SQS) for Docker Compose only. Built once, then cached.
FROM public.ecr.aws/docker/library/python:3.13-slim
RUN pip install --no-cache-dir "moto[server]==5.2.4"
EXPOSE 5000
CMD ["moto_server", "-H", "0.0.0.0", "-p", "5000"]
