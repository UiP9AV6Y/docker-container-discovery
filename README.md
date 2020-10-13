# Docker Container Discovery

*Docker Container Discovery* (DCD) is a service discovery tool for Docker
containers. It exposes container addresses via DNS as they come and go.
Utilizing a templating system, the available records can be adjusted to various
deployment scenarios.

The server provides 2 interfaces; a DNS service and a HTTP endpoint providing
application metrics for consumption by Prometheus.

The DNS service provides SOA, NS, A and PTR records.

The *NS* record is merely advertising the (public side of the) service itself.

The *SOA* record is composed of configurable values. The serial number is
the timestamp of the last time a Docker container was added or removed.

*PTR* records point to the domain names composed of container IDs.

*A* records are generated from domain templates. One record can point to multiple
containers, in which case the DNS service will respond with all of the matched
addresses.

The **examples** directory contains possible usecases.

## Domain templates

The template system is the key to extracting domain names from Docker
containers. Values can contain lookup tokens to generate customized values
per container. Tokens are identified by enclosing the lookup with curly
brackets (e.g. {label.test}).

Domain names are only used if all tokens resolve to a non-empty value.

The first part of a lookup is the section of the container which the lookup is
performed against. Valid values include:

* label

  Extract the value from the container labels. The lookup key is the name of
  the label whose value is to be used.

* container

  Use container information to generate the domain name. Available keys include:

  * name

    The name of the container

* image

  Use image information to generate the domain name. Available keys include:

  * name

  The name of the image. Non-alphanumeric characters are replaced with hyphens.
  (e.g. **example_company/my_server** becomes *example-company-my-server*)

  * ident

  The last part of the image name
  (e.g. **example_company/my_server** becomes *my-server*)

  * provider

  The second-to-last part of the image name
  (e.g. **example_company/my_server** becomes *example-company*)

Examples:

Assuming we have a container with the following information:

* image: redis
* container name: my-server
* labels:

  * com.example.company=example
  * com.example.department=docker

Using these templates...

* {image.ident}
* {label.com.example.company}.company
* {container.name}.{image.name}
* {label.org.example.test}.test
* {image.provider}

... results in the following domain names:

* redis
* example.company
* my-server.redis

The last two templates have unresolvable tokens and therefor yield no result.

## Container labels

Some aspects of the container treatment can be configured on the respective
container directly. This includes domain names as well as address advertisement
instructions. The information is extracted from the container labels:

* com.docker.container-discovery/ignore

  Containers where this label exists with the value **true** are not registered
  with the DNS service.

* com.docker.container-discovery/advertise

  Address to use for advertisement of the container. If it contains a netmask
  length (e.g. 192.168.2.0/24), the container addresses are matched against it.

* com.docker.container-discovery/ident.\*

  The value of labels starting with this prefix are used verbatim as
  domain names for the container.

## Usage

The behaviour of *DCD* can be controlled via commandline argument or environment
variables, with the former taking precedence.
Arguments which do not accept a value, can be
enabled via environment variables whose value
are *true*, *yes*, *on*, or *1*. To invert
their behaviour use *false*, *no*, *off, or *0*.

* `--domain-template` (**DCD_DOMAIN_TEMPLATE**)

  Domain template to apply on container meta data to receive domain names.
  Names are only registered if **all** tokens can be resolved. Providing
  multiple values via environment variables can be achived by using arbitrary
  postfixes for the variable keys (e.g. **DCD_DOMAIN_TEMPLATE_1**)

* `--docker-socket` (**DCD_DOCKER_SOCKET**)

  Path to the socket for listening to Docker events.

  Default: /var/run/docker.sock

* `--docker-host` (**DCD_DOCKER_HOST**)

  Host to connect to for Docker events.
  Uses TCP for communication instead of a unix
  socket like `--docker-socket`.

* `--docker-port` (**DCD_DOCKER_PORT**)

  Port to connect to for Docker events.
  Only usable in combination with `--docker-host`.

  Default: 2375

* `docker-tls-verify` (**DOCKER_TLS_VERIFY**)

  Verify the connection with the remote docker server.

* `docker-tls-cacert` (**DOCKER_TLS_CACERT**)

  CA file for the TLS connection to
  the remote docker server.

* `docker-tls-cert` (**DOCKER_TLS_CERT**)

  Client cert for the TLS connection to
  the remote docker server.

* `docker-tls-key` (**DOCKER_TLS_KEY**)

  Client key for the TLS connection to
  the remote docker server.

* `--connect-retries` (**DCD_CONNECT_RETRIES**)

  Number of retries to connect to remote docker.
  Only really useful when connecting via TCP using
  `--docker-host`.

  Default: 0

* `--connect-timeout` (**DCD_CONNECT_TIMEOUT**)

  Seconds to wait between reconnects.

  Default: 5

* `--container-cidr` (**DCD_CONTAINER_CIDR**)

  Filter for container addresses. If a container has multiple addresses
  (e.g. b/c it is attached to multiple networks), this filter will help to limit
  the selection of addresses to advertise. The first address to match, will be
  advertised via the DNS service. If no value is provided, the first address of
  all available values is used.

* `--tld` (**DCD_TLD**)

  Top level domain to attach to all FQDNs provided by this server. The DNS
  service will provide a SOA record for this value as well.

  Default: docker.

* `--advertise` (**DCD_ADVERTISE**)

  IP address to expose the DNS service itself. This is mainly used for the
  NS record.
  The value can include a netmask length (e.g. 192.168.2.0/24), in which case
  the local interface addresses are matched against it to receive the
  advertised value. When absent, the first interface address is used.

* `--refresh` (**DCD_REFRESH**)

  *Refresh* value in seconds for the SOA record.

  Default: 1200

* `--retry` (**DCD_RETRY**)

  *Retry* value in seconds for the SOA record.

  Default: 900

* `--expire` (**DCD_EXPIRE**)

  *Expire* value in seconds for the SOA record.

  Default: 3600000

* `--min-ttl` (**DCD_MIN_TTL**)

  *Min TTL* value in seconds for the SOA record.

  Default: 172800

* `--bind` (**DCD_BIND**)

  Address to bind the DNS service to.

  Default: 0.0.0.0

* `--port` (**DCD_PORT**)

  Port to bind the DNS service to.

  Default: 10053

* `--proto` (**DCD_PROTO**)

  Traffic protocol for the DNS service.

  Valid values: tcp, udp, both

  Default: both

* `--web-bind` (**DCD_WEB_BIND**)

  Address to bind the web werver to.

  Default: 0.0.0.0

* `--web-port` (**DCD_WEB_PORT**)

  Port to bind the web server to.

  Default: 19053

* `--log-format` (**DCD_LOG_FORMAT**)

  Output format.

  Valid values: simple, terminal, structured

  Default: simple

* `--verbosity` (**DCD_VERBOSITY**)

  Output verbosity.

  Valid values: fatal, error, warning, info, debug

  Default: info

## Alternatives

* [gliderlabs/registrator](http://gliderlabs.com/registrator) + [consul](https://www.consul.io/)
* [docker-dns](https://github.com/bnfinet/docker-dns)
* [dnsdock](https://github.com/aacebedo/dnsdock)

## License

MIT
