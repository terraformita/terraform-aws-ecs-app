#!/usr/bin/env bash
set -e

LAMBDA_DIR="$(pwd)"
LAYER_ZIP="sdk-layer.zip"
DST_FOLDER="python"

# Remove existing SDK layer ZIP file if exists
[[ -s $LAYER_ZIP ]] && rm -f $LAYER_ZIP
rm -rf $DST_FOLDER

# Pull and run Amazon Linux 2023 container
DOCKER_IMAGE="amazonlinux"
PLATFORM_FLAG=""

# Detect Apple Silicon and set platform flag
if [[ $(uname -m) == "arm64" ]]; then
  PLATFORM_FLAG="--platform linux/amd64"
fi

docker pull $PLATFORM_FLAG $DOCKER_IMAGE
docker run -v "$LAMBDA_DIR:/lambda" -w /lambda --rm -i $PLATFORM_FLAG $DOCKER_IMAGE bash << EOF
  set -e

  # Install necessary packages
  yum install -y gcc python3.12 python3.12-devel

  # Create and activate virtual environment
  python3.12 -m venv venv
  source venv/bin/activate

  # Install dependencies
  pip3.12 install pipreqs
  pipreqs .
  pip3 install -r requirements.txt --target ${DST_FOLDER}
  pip3 install requests-aws4auth --upgrade --target ${DST_FOLDER}
  pip3 install requests --upgrade --target ${DST_FOLDER}
  pip3 install pyjwt["crypto"] --upgrade --target ${DST_FOLDER}

  # Create the ZIP archive
  zip -r $LAYER_ZIP ${DST_FOLDER}/

  # Deactivate virtual environment
  deactivate
  rm -rf venv python
EOF

# Confirm success
echo "Lambda SDK layer successfully built: $LAYER_ZIP"
