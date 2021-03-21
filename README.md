# sks-keyserver-clustering
Running SKS cluster setup for optimal performance on keyserver.dobrev.eu

# Requirements
* Ubuntu 20.04
* Hockeypuck 2.1.0 + [patches for SKS compataility](https://github.com/mclueppers/hockeypuck/tree/sks-compatability)
* Five server nodes for clustering (1x Apache2+Varnish, 2x Hockeypuck, 2x PostgreSQL)

# Target architecture
Incoming requests are handled by a frontend server running Apache2 and Varnish cache. The latter acts as load-balancer for the underlying pair of Hockeypuck nodes. Each backend is wired to an individual PostgreSQL instance.

TODO: draw a nice diagram
# Initial setup
Install Ubuntu 20.04 minimal on all five nodes. I'm using following IPs for convinience:
* frontend - 10.0.0.211 and [real IP]
* hockeypuck01 - 10.0.0.212
* hockeypuck02 - 10.0.0.213
* postgresql01 - 10.0.0.214
* postgresql02 - 10.0.0.215

## Frontend
Install Apache2 and Varnish cache. Copy configuration from [etc](./etc) and start services. I'm using Varnish to cache requests for 5 minutes. This is a greatly offloading both backend servers and they can focus to recon processing.

```
# Frontend server
apt install -y apache2 varnish

# From your station with this repository clone
scp -rp ./etc/varnish ./etc/apache2/sites-available/ root@10.0.0.211:/etc

# Back to frontend server
a2enmod rewrite proxy proxy_http
service apache2 restart
service varnish restart
```

## Database nodes
Install PostgreSQL 12 on both nodes and create role and database for Hockeypuck. Allow remote access from your backend nodes in `pg_hba.conf`

```
apt install -y postgresql-12 postgresql-client-12
sudo -u postgres -s
echo "CREATE USER hockeypuck WITH PASSWORD 'changeme'; CREATE DATABASE hkp; ALTER DATABASE hkp TO OWNER hockeypuck;" | psql
```
## Hockeypuck node(s)
Clone the SKS compat version from my Hockeypock fork [here](https://github.com/mclueppers/hockeypuck/tree/sks-compatability)

```
git clone https://github.com/mclueppers/hockeypuck.git
cd hockeypuck
git checkout sks-compatability
make install-build-depends
debuild -- binary
```

**Problem 1** `debuild` fails because `golang-1.12` is not available in Ubuntu 20.04. **Solution 1** Change `debian/control` and require `golang-1.13`

Copy Hockeypuck [configuration](./etc/hockeypuck/hockeypuck.conf) to the node(s). Don't forget to change IPs when setting up the second node. You can start Hockeypuck now and enjoy a load-balanced cluster.

```
# From your install node
scp ./etc/hockeypuck 10.0.0.212:/etc/

# From hockeypuck01
dpkg -i hockeypuck_2.1.0_1.<GITSHA>.deb
```

## Recon ingress with Linux IPVS
For ingress recon connections you can use Linux IPVS subsytem to balance them between your backends

```
ipvsadm -a -t 10.0.0.211:11370 -r 10.0.0.212:11370 -m
ipvsadm -a -t 10.0.0.211:11370 -r 10.0.0.213:11370 -m
```
