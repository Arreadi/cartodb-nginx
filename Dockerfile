#
# Cartodb container
#
FROM ubuntu:14.04
MAINTAINER Stefan Verhoeven <s.verhoeven@esciencecenter.nl>

# Configuring locales
ENV DEBIAN_FRONTEND noninteractive
RUN dpkg-reconfigure locales && \
      locale-gen en_US.UTF-8 && \
      update-locale LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN apt-get update && \
  useradd -m -d /home/cartodb -s /bin/bash cartodb &&\
  apt-get install -y -q software-properties-common &&\
  add-apt-repository -y ppa:chris-lea/node.js &&\
  apt-get update &&\
  apt-get install -y -q \
    build-essential \
    autoconf \
    automake \
    libtool \
    checkinstall \
    unp \
    zip \
    unzip \
    git-core \
    git \
    subversion \
    curl \
    libgeos-c1 \
    libgeos-dev \
    libjson0 \
    python-simplejson \
    libjson0-dev \
    proj-bin \
    proj-data \
    libproj-dev \
    gdal-bin \
    libgdal1-dev \
    postgresql-9.3 \
    postgresql-client-9.3 \
    postgresql-contrib-9.3 \
    postgresql-server-dev-9.3 \
    postgresql-plpython-9.3 \
    postgresql-9.3-postgis-2.1 \
    postgresql-9.3-postgis-2.1-scripts \
    postgis \
    nodejs \
    redis-server \
    python2.7-dev \
    python-setuptools \
    varnish \
    imagemagick \
    libmapnik-dev \
    mapnik-utils \
    python-mapnik \
    python-argparse \
    python-gdal \
    python-chardet \
    openssl \
    libreadline6 \
    zlib1g \
    zlib1g-dev \
    libssl-dev \
    libyaml-dev \
    libsqlite3-dev \
    sqlite3 \
    libxml2-dev \
    libxslt-dev \
    libc6-dev \
    ncurses-dev \
    bison \
    pkg-config \
    libpq5 \
    libpq-dev \
    libcurl4-gnutls-dev \
    libffi-dev \
    libgdbm-dev \
    gnupg \
    libreadline6-dev \
    libcairo2-dev \
    libjpeg8-dev \
    libpango1.0-dev \
    libgif-dev \
    pgtune \
    nginx \
  --no-install-recommends &&\
  rm -rf /var/lib/apt/lists/*
ADD config/cartodb.nginx.proxy.conf /etc/nginx/conf.d/
# Install rvm
RUN gpg --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3
RUN curl -L https://get.rvm.io | bash -s stable --ruby
RUN echo 'source /usr/local/rvm/scripts/rvm' >> /etc/bash.bashrc
RUN /bin/bash -l -c rvm requirements
ENV PATH /usr/local/rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN echo rvm_max_time_flag=15 >> ~/.rvmrc
RUN /bin/bash -l -c 'rvm install 1.9.3-p547 --patch railsexpress'
RUN /bin/bash -l -c 'rvm use 1.9.3-p547 --default'
RUN /bin/bash -l -c 'gem install bundle archive-tar-minitar'

# Install bundler
RUN /bin/bash -l -c 'gem install bundler --no-doc --no-ri'

# Setting PostgreSQL
RUN sed -i 's/\(peer\|md5\)/trust/' /etc/postgresql/9.3/main/pg_hba.conf && \
      pgtune -T Web -c 100 -i /etc/postgresql/9.3/main/postgresql.conf -o /etc/postgresql/9.3/main/postgresql.conf.pgtune && \
      mv /etc/postgresql/9.3/main/postgresql.conf /etc/postgresql/9.3/main/postgresql.conf.orig && \
      mv /etc/postgresql/9.3/main/postgresql.conf.pgtune /etc/postgresql/9.3/main/postgresql.conf

# Install schema_triggers
RUN git clone https://github.com/CartoDB/pg_schema_triggers.git && \
      cd pg_schema_triggers && \
      make all install && \
      sed -i \
      "/#shared_preload/a shared_preload_libraries = 'schema_triggers.so'" \
      /etc/postgresql/9.3/main/postgresql.conf
ADD ./template_postgis.sh /tmp/template_postgis.sh
RUN service postgresql start && /bin/su postgres -c \
      /tmp/template_postgis.sh && service postgresql stop

# Install cartodb extension
RUN git clone https://github.com/CartoDB/cartodb-postgresql && \
      cd cartodb-postgresql && \
      PGUSER=postgres make install
ADD ./cartodb_pgsql.sh /tmp/cartodb_pgsql.sh
RUN service postgresql start && /bin/su postgres -c \
      /tmp/cartodb_pgsql.sh && service postgresql stop

# Install CartoDB API
RUN git clone git://github.com/CartoDB/CartoDB-SQL-API.git && \
      cd CartoDB-SQL-API && ./configure && npm install

# Install Windshaft
RUN git clone git://github.com/CartoDB/Windshaft-cartodb.git && \
      cd Windshaft-cartodb && ./configure && npm install && mkdir logs

# Install CartoDB (with the bug correction on bundle install)
RUN git clone git://github.com/CartoDB/cartodb.git && \
      cd cartodb && /bin/bash -l -c 'bundle install' || \
      /bin/bash -l -c "cd $(/bin/bash -l -c 'gem contents \
            debugger-ruby_core_source' | grep CHANGELOG | sed -e \
            's,CHANGELOG.md,,') && /bin/bash -l -c 'rake add_source \
            VERSION=$(/bin/bash -l -c 'ruby --version' | awk \
            '{print $2}' | sed -e 's,p55,-p55,' )' && cd /cartodb && \
            /bin/bash -l -c 'bundle install'"

# Copy confs
ADD ./config/CartoDB-dev.js \
      /CartoDB-SQL-API/config/environments/development.js
ADD ./config/WS-dev.js \
      /Windshaft-cartodb/config/environments/development.js
ADD ./config/app_config.yml /cartodb/config/app_config.yml
ADD ./config/database.yml /cartodb/config/database.yml
ADD ./create_dev_user /cartodb/script/create_dev_user
ADD ./setup_organization.sh /cartodb/script/setup_organization.sh
ENV PATH /usr/local/rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN service postgresql start && service redis-server start && \
	bash -l -c "cd /cartodb && bash script/create_dev_user && bash script/setup_organization.sh" && \
	service postgresql stop && service redis-server stop

EXPOSE 3000 8080 8181

ADD ./startup.sh /opt/startup.sh
CMD ["/bin/bash", "/opt/startup.sh"]
