FROM debian:stretch

# I would typically just use FROM golang:1.10, but...
# Rules of the game say from base os package.
# But... none of the docker library images every use COPY or ADD, so...
# Let's just rebuild go

#######################################################################
# https://github.com/docker-library/buildpack-deps/blob/b0fc01aa5e3aed6820d8fed6f3301e0542fbeb36/stretch/curl/Dockerfile

RUN apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		netbase \
		wget \
	&& rm -rf /var/lib/apt/lists/*

RUN set -ex; \
	if ! command -v gpg > /dev/null; then \
		apt-get update; \
		apt-get install -y --no-install-recommends \
			gnupg \
			dirmngr \
		; \
		rm -rf /var/lib/apt/lists/*; \
	fi


#######################################################################
# We are now effectively
# FROM buildpack-deps:stretch-curl
# https://github.com/docker-library/buildpack-deps/blob/1845b3f918f69b4c97912b0d4d68a5658458e84f/stretch/scm/Dockerfile

# procps is very common in build systems, and is a reasonably small package
RUN apt-get update && apt-get install -y --no-install-recommends \
		bzr \
		git \
		mercurial \
		openssh-client \
		subversion \
		\
		procps \
	&& rm -rf /var/lib/apt/lists/*


#######################################################################
# FROM buildpack-deps:stretch-scm
# https://github.com/docker-library/golang/blob/329b6672949337c4469351b2e8b8575459a75c7f/1.10/stretch/Dockerfile

# gcc for cgo
RUN apt-get update && apt-get install -y --no-install-recommends \
		g++ \
		gcc \
		libc6-dev \
		make \
		pkg-config \
	&& rm -rf /var/lib/apt/lists/*

ENV GOLANG_VERSION 1.10.2

RUN set -eux; \
	\
# this "case" statement is generated via "update.sh"
	dpkgArch="$(dpkg --print-architecture)"; \
	case "${dpkgArch##*-}" in \
		amd64) goRelArch='linux-amd64'; goRelSha256='4b677d698c65370afa33757b6954ade60347aaca310ea92a63ed717d7cb0c2ff' ;; \
		armhf) goRelArch='linux-armv6l'; goRelSha256='529a16b531d4561572db6ba9d357215b58a1953437a63e76dc0c597be9e25dd2' ;; \
		arm64) goRelArch='linux-arm64'; goRelSha256='d6af66c71b12d63c754d5bf49c3007dc1c9821eb1a945118bfd5a539a327c4c8' ;; \
		i386) goRelArch='linux-386'; goRelSha256='ea4caddf76b86ed5d101a61bc9a273be5b24d81f0567270bb4d5beaaded9b567' ;; \
		ppc64el) goRelArch='linux-ppc64le'; goRelSha256='f0748502c90e9784b6368937f1d157913d18acdae72ac75add50e5c0c9efc85c' ;; \
		s390x) goRelArch='linux-s390x'; goRelSha256='2266b7ebdbca13c21a1f6039c9f6887cd2c01617d1e2716ff4595307a0da1d46' ;; \
		*) goRelArch='src'; goRelSha256='6264609c6b9cd8ed8e02ca84605d727ce1898d74efa79841660b2e3e985a98bd'; \
			echo >&2; echo >&2 "warning: current architecture ($dpkgArch) does not have a corresponding Go binary release; will be building from source"; echo >&2 ;; \
	esac; \
	\
	url="https://golang.org/dl/go${GOLANG_VERSION}.${goRelArch}.tar.gz"; \
	wget -O go.tgz "$url"; \
	echo "${goRelSha256} *go.tgz" | sha256sum -c -; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	\
	if [ "$goRelArch" = 'src' ]; then \
		echo >&2; \
		echo >&2 'error: UNIMPLEMENTED'; \
		echo >&2 'TODO install golang-any from jessie-backports for GOROOT_BOOTSTRAP (and uninstall after build)'; \
		echo >&2; \
		exit 1; \
	fi; \
	\
	export PATH="/usr/local/go/bin:$PATH"; \
	go version

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"
WORKDIR $GOPATH

#######################################################################
# FROM golang:1.10
# The rest is from local .travis.yml, with minimal rewriting into a Dockerfile.

COPY . /go/src/github.com/mholt/caddy

RUN cd /go/src/github.com/mholt/caddy \
 && go get github.com/golang/lint/golint \
 && go get github.com/FiloSottile/vendorcheck \
 && go get github.com/alecthomas/gometalinter

# && bash generate_gitcookies.sh \
RUN cd /go/src/github.com/mholt/caddy \
 && go get -t ./...

RUN cd /go/src/github.com/mholt/caddy \
 && gometalinter --install \
 && gometalinter --disable-all -E vet -E gofmt -E misspell -E ineffassign -E goimports -E deadcode --tests --vendor ./... \
 && vendorcheck ./... \
 && go test -race ./... \
 && golint ./...

ENTRYPOINT ["caddy"]
