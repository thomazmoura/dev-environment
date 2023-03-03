if [ -z "$1" ]; then
    echo "You need to inform what is the image you're building."
    return 1;
else
    CACHE_IMAGE=$1
fi

if [ -z "$2" ]; then
    GIT_BRANCH="latest"
else
    GIT_BRANCH="$2"
fi

echo -e "\nBuilding base Dockerfile from $CACHE_IMAGE"
docker build --cache-from $CACHE_IMAGE:base --cache-from $CACHE_IMAGE:base_$GIT_BRANCH --tag $CACHE_IMAGE:base_$GIT_BRANCH --build-arg BUILDKIT_INLINE_CACHE=1 --file base.Dockerfile .

echo -e "\nBuilding Dockerfile from $CACHE_IMAGE"
docker build --cache-from $CACHE_IMAGE:latest --tag $CACHE_IMAGE:$GIT_BRANCH --build-arg BUILDKIT_INLINE_CACHE=1 --build-arg DockerBase="$CACHE_IMAGE:base_$GIT_BRANCH" --file Dockerfile .