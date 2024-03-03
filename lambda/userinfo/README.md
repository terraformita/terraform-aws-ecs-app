# Build Lambda Layer

**IMPORTANT**. In order for Lambda to run successfully, make sure to build all Python modules on Amazon Linux 2 box.

## Run AmazonLinux2 Container

- `docker pull amazonlinux` - pull amazonlinux image from [Docker Hub](https://hub.docker.com/_/amazonlinux)
- `docker run -v {path_to_lambda_folder}:/lambda --rm -it amazonlinux bash` - run amazonlinux image and mount the `path to lambda_folder` as `/lambda` in the container. 

**NOTE** For M1/M2/Mx add `--platform linux/amd64` to the `docker run` command

- Install necessary pre-requisites (specifically, [Python 3.8](https://techviewleo.com/how-to-install-python-on-amazon-linux/)):

```bash
yum install python
yum install gcc
amazon-linux-extras | grep -i python
amazon-linux-extras enable python3.8
yum install python38 python38-devel
```

## Build Lambda SDK Layer

Execute the following commands inside the running container:

- `cd /lambda` - chdir to the mounted lambda directory
- `python3.8 -m venv venv` <- to enable virtual environment
- `source venv/bin/activate` <- to activate virtual environment
- `pip3.8 install pipreqs`
- `pipreqs .` <- to build "requirements.txt" file
- `pip3.8 install -r requirements.txt --target <dst_folder>` <- to download required modules into `<dst_folder>`
- `pip3.8 install requests-aws4auth --upgrade --target <dst_folder>` <- to download `requests-aws4auth` module needed for signing HTTP requests
- `pip3.8 install requests --upgrade --target <dst_folder>` <- to download `requests` module needed for proper working of the Elasticsearch module.
- `pip3.8 install pyjwt["crypto"] --upgrade --target <dst_folder>` <- to download `pyjwt`'s cryptographics module needed for proper working of JWT token decryption.
- `zip -r sdk-layer.zip <dst_folder>/` <- to create ZIP archive with the lambda layer
- `deactivate` <- to exit virtual environment
