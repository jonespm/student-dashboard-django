# build react components for production mode
FROM node:11.10-alpine AS node-webpack
WORKDIR /usr/src/app

# NOTE: package.json and webpack.config.js not likely to change between dev builds
COPY package.json webpack.config.js /usr/src/app/
RUN npm install

# NOTE: assets/ likely to change between dev builds
COPY assets /usr/src/app/assets
RUN npm run prod 

# This is to find and remove symlinks that break some Docker builds.
# We we need these later we'll just uncompress them 
# Also remove src and the symlinks afterward
RUN apk --update add tar && \ 
    find . -type l -print0 | tar -cvf node_modules_symlinks.tgz --null -T - && \
    rm -rf /usr/src/app/assets/src && \
    find . -type l -print0 | xargs -0 rm -rf

# build node libraries for production mode
FROM node:11.10-alpine AS node-prod-deps

COPY --from=node-webpack /usr/src/app /usr/src/app
RUN npm prune --production && \
    # This is needed to clean up the examples files as these cause collectstatic to fail (and take up extra space)
    find /usr/src/app/node_modules -type d -name "examples" -print0 | xargs -0 rm -rf

# FROM directive instructing base image to build upon
FROM python:3.6 AS app

# EXPOSE port 5000 to allow communication to/from server
EXPOSE 5000
WORKDIR /code

# NOTE: requirements.txt not likely to change between dev builds
COPY requirements.txt /code/requirements.txt
RUN apt-get update && \
    apt-get install -y --no-install-recommends netcat vim-tiny jq python3-dev xmlsec1 cron && \
    apt-get clean -y && \
    pip install -r requirements.txt

# copy built react and node libraries for production mode
COPY --from=node-prod-deps /usr/src/app/package-lock.json /code/package-lock.json
COPY --from=node-prod-deps /usr/src/app/webpack-stats.json /code/webpack-stats.json
COPY --from=node-prod-deps /usr/src/app/assets /code/assets
COPY --from=node-prod-deps /usr/src/app/node_modules /code/node_modules

# NOTE: project files likely to change between dev builds
COPY . /code/

# This DJANGO_SECRET_KEY is set here just so collectstatic runs with an empty key. It can be set to anything
RUN echo yes | DJANGO_SECRET_KEY="collectstatic" python manage.py collectstatic --verbosity 0

# Sets the local timezone of the docker image
ARG TZ
ENV TZ ${TZ:-America/Detroit}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

CMD ["/code/start.sh"]
# done!