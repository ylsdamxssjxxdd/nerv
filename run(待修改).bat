echo Set variables
SET VERSION=1
SET IMAGE_PATH=.\neural_images\image%VERSION%.tar
SET COMPOSE_PATH=.\dockerfiles\docker-compose.yml
SET IMAGE_NAME=neural_image
SET IMAGE_TAG=%VERSION%

echo Load the Docker image
docker load -i "%IMAGE_PATH%"

REM Run the Docker compose
docker-compose -f "%COMPOSE_PATH%" -p neural_compose%VERSION% up


echo Done.