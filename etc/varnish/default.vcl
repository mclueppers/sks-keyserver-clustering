#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and https://www.varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;
import std;
import directors;    # load the directors

# Default backend definition. Set this to point to your content server.

backend hockeypuck01 {
    .host = "10.0.0.212";
    .port = "11371";
}

backend hockeypuck02 {
    .host = "10.0.0.213";
    .port = "11371";
}

sub vcl_init {
    new sksdb = directors.round_robin();
    sksdb.add_backend(hockeypuck01);
    sksdb.add_backend(hockeypuck02);
}

sub vcl_synth {
    if (resp.status == 503 && req.http.sie-enabled) {
        unset req.http.sie-enabled;
        return (deliver);
    }
}

sub vcl_hit {
    if (obj.ttl < 0s && obj.ttl + obj.grace > 0s) {
        if (req.restarts == 0) {
            set req.http.sie-enabled = true;
            return (fetch);
        } else {
            set req.http.sie-abandon = true;
            return (deliver);
        }
    }

    if (obj.ttl >= 0s) {
        return (deliver);
    }

    return (fetch);
    # Varnish Cache 5 needs to not fetch -> return (miss);
}

sub vcl_recv {
    # Happens before we check if we have this in cache already.
    #
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.
    set req.backend_hint = sksdb.backend();
    
    unset req.http.f-forwarded-for;
 
    if (std.healthy(req.backend_hint)) {
        set req.http.grace = 300;
    } else {
        set req.http.grace = 3600;
    }
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    #
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.
    if (beresp.status == 500 || beresp.status == 502 ||
        beresp.status == 503) {
    
        #set beresp.saintmode = 10s;

        #if (req.method != "POST") {
            return(retry);
        #}
    }


    if (beresp.ttl > 0s) {
        /* Remove Expires from backend, it's not long enough */
        unset beresp.http.expires;

        /* Set the clients TTL on this object to 300 seconds (5m) */
        set beresp.http.Cache-Control = "max-age=300";

        /* Set how long Varnish will keep it */
        set beresp.ttl = 5m;

	if (beresp.http.content-type ~ "application/pgp-keys") {
          /* marker for vcl_deliver to reset Age: */
          set beresp.http.magicmarker = "1";
        }

	/* Set the grace period to 1 hour */
        set beresp.grace = 1h;
    }

    if (beresp.http.content-type ~ "application/pgp-keys") {
        if (std.integer(beresp.http.Content-Length,0) < 50000000 /* max size in bytes */ ) {
            if (beresp.status == 200) { /* backend returned 200 */
                set beresp.ttl = 1h; /* cache for one hour */
            }
        }
    }
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.
    # Remove some headers to shorthen the response size
    unset resp.http.Via;
    unset resp.http.X-Varnish;
    unset resp.http.Pragma;

    if (resp.http.magicmarker) {
        /* Remove the magic marker */
        unset resp.http.magicmarker;

        /* By definition we have a fresh object */
        set resp.http.Age = "0";
    }
}
