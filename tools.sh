#!/bin/zsh

set -eu 
set -o errexit
set -o pipefail
set -o nounset

MINIO_IMAGE_NAME=quay.io/minio/minio
MINIO_CONTAINER_NAME=minio_lambda
POSTGRES_IMAGE_NAME=postgres_lambda
POSTGRES_CONTAINER_NAME=postgres_lambda

function copyConfig() {
  mkdir -p ~/.swiftSampleDemo; cp swiftLambdaDemo.json ~/.swiftSampleDemo/swiftLambdaDemo.json
}

function stopServices() {
  stopS3
  stopDatabase
}

function startServices() {
  stopServices
  startS3
  startDatabase
}

function stopContainerNamed() {

  if [ $# -eq 0 ]; then
    echo "Usage: stopContainerNamed <container name>"
    exit 1
  fi

  container_name=$1 
  
  container=$(docker ps -a --filter "name=^/$container_name$" --format "{{.Names}}")
  if [ "$container" = "$container_name" ]; then
    echo "Container $container_name exists. Stopping and removing"
    docker stop "$container_name"
    docker rm "$container_name"
  fi  
}

function stopS3() {
  stopContainerNamed $MINIO_CONTAINER_NAME 
}

function startS3() {
  mkdir -p ${HOME}/minio/data/org.gestrich.sandbox
  docker run \
     -d \
     -p 9000:9000 \
     -p 9001:9001 \
     --user $(id -u):$(id -g) \
     --name $MINIO_CONTAINER_NAME \
     -e "MINIO_ROOT_USER=admin" \
     -e "MINIO_ROOT_PASSWORD=password" \
     -v ${HOME}/minio/data:/data \
     quay.io/minio/minio server /data --console-address ":9001"
}

function stopDatabase() {
  stopContainerNamed $POSTGRES_CONTAINER_NAME
}

function startDatabase() {

  docker build \
    --build-arg "EXPOSE_PORT=5432" \
    --build-arg "USERNAME=docker" \
    --build-arg "PASSWORD='docker'" \
    -t $POSTGRES_IMAGE_NAME \
    -f PostgresDockerfile .

  docker run \
    -d \
    -P \
    -p 5432:5432 \
    --name $POSTGRES_IMAGE_NAME \
    $POSTGRES_IMAGE_NAME
}

function killServer() {

  # Use lsof to find processes that are listening on localhost port 7000
  PIDS=$(lsof -i :7000 | grep "TCP localhost" | awk '{print $2}')

  if [ -z "$PIDS" ]; then
      echo "No processes found on localhost port 7000."
  else
      # Use a while loop to read each line (PID) and kill the process
      echo "$PIDS" | while read -r PID; do
          echo "Killing process with PID: $PID on localhost port 7000"
          kill "$PID"
      done
  fi  

}

function startDynamoDB() {
  docker run -p 8000:8000 amazon/dynamodb-local
}

function tailLogs(){

  export AWS_PROFILE="production";
  groupPrefix="Sugar"

  group="$(aws logs  describe-log-groups --log-group-name-prefix "/aws/lambda/$groupPrefix" | jq -r  ".logGroups[0].logGroupName")";
  #aws logs tail "$group" --since 12h
  aws logs tail "$group" --follow
}

function tailLogsDev(){

  export AWS_PROFILE="sandbox";
  groupPrefix="SugarMonitorDev"

  group="$(aws logs  describe-log-groups --log-group-name-prefix "/aws/lambda/$groupPrefix" | jq -r  ".logGroups[0].logGroupName")";
  #aws logs tail "$group" --since 12h
  aws logs tail "$group" --follow
}

function loopLogs(){
aws dynamodb execute-statement  --statement "SELECT * FROM \"sugar-monitor\" WHERE partitionKey='LoopLog' AND sort > '2022-12-04T16:34' AND contains(message, 'Remote Notification')" \
  | jq -r '.Items[] | "\(.sort) \(.message)"' | jq
}


#function uploadLambda(){
#  aws s3 cp lambda.zip s3://org.gestrich.sugarmonitor;
#  aws lambda update-function-code --function-name sugarMonitor --s3-bucket org.gestrich.sugarmonitor --s3-key lambda.zip;
#  aws lambda -- publish-version --function-name sugarMonitor --description "Updates";
#}

#function pushSugarMonitor(){
#  description="$(git log --format=%B -n 1 HEAD)";
#  echo "Using description: $description"
#  ${SWIFT_SERVER_TOOLS_PATH}/lambda/custom-deploy/tools.sh buildAndPublish ~/.ssh SugarMonitor sugarMonitor "$description"
#}

#function testLocalMonitor(){
#  curl --header "Content-Type: application/json" \
#  --request POST   \
#  --data '{"action": "monitor", "save": true}' \
#  http://localhost:7000/invoke | jq
#}

#Postgres + Docker

#name="postgres_lambda"

#function localStartPostgresDatabase(){
#    if [[  $(docker ps --filter "name=^/$name$" --format '{{.Names}}') == $name ]]; then
#      echo "$name Database already running"
#    else
#      docker build -t $name -f postgres_docker/Dockerfile .
#      docker run -d --rm -P -p 5436:5432 --name $name $name
#      echo "$name Database now running"
#    fi
#}

#function localNukePostgresDatabase(){
#    if [[  $(docker ps --filter "name=^/$name$" --format '{{.Names}}') == $name ]]; then
#      docker stop $name
#      echo "$name Database Removed"
#    else
#      echo "$name Database not running"
#    fi
#}


# Check if the function exists
  if [ $# -gt 0 ]; then 
#if declare -f "$1" > /dev/null
  # call arguments verbatim
  "$@"
else
  # Show a helpful error
  echo "Functions Available:"
  typeset -f | awk '!/^main[ (]/ && /^[^ {}]+ *\(\)/ { gsub(/[()]/, "", $1); print $1}'
  exit 1
fi
