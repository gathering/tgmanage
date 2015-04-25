#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and http://varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

acl einstein {
    "localhost";    # myself
    "185.12.59.12"; # and everyone on the local network
    "2a02:ed02:1337::12";
}

sub vcl_recv {
	if (req.url ~ "nightMode") {
		set req.url = regsub(req.url, "nightMode","");
		set req.url = req.url + "?nightMode";
	}
    # Happens before we check if we have this in cache already.
    # 
    # Typically you clean up the request here, removing cookies you don't need,
    # rewriting the request, etc.
if (req.restarts == 0) {
  if (req.http.X-Forwarded-For) {
    set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
  } else {
    set req.http.X-Forwarded-For = client.ip;
  }
}

	if (client.ip ~ einstein){
		set req.http.x-einstein = "true";
	} else {
		set req.http.x-einstein = "false";
	}

    if (req.http.host ~ "stream") {
	    return (pass);
    }

    if (req.http.host ~ "nms-public"){
	    return (pass);
    }

     if (req.method != "GET" &&
       req.method != "HEAD" &&
       req.method != "PUT" &&
       req.method != "POST" &&
       req.method != "TRACE" &&
       req.method != "OPTIONS" &&
       req.method != "DELETE") {
         /* Non-RFC2616 or CONNECT which is weird. */
         return (pipe);
     }
 
     if (req.method != "GET" && req.method != "HEAD") {
         /* We only deal with GET and HEAD by default */
         return (pass);
     }
    
     unset req.http.Cookie;
     if (req.http.Cookie) {
         /* Not cacheable by default */
         return (pass);
     }

     return (hash);
 }
sub vcl_hash {
    hash_data(req.http.x-einstein);
    hash_data(req.http.authorization);
}
sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    # 
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.
    if (!(bereq.http.host ~ "stream")) {
	    if (beresp.status == 200) {
		    set beresp.ttl = 2s;
	    } else {
		    set beresp.ttl = 0s;
	    }
	    if(bereq.url ~ "port-state.pl" && beresp.status == 200) {
		    set beresp.ttl = 1s;
	    }
	    if (beresp.status == 200 && bereq.url ~ "now=") {
		    set beresp.ttl = 60m;
	    }
	    if (beresp.status == 500) {
		    return (retry);
	    }
    }

}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    # 
    # You can do accounting or modifying the final object here.
}
sub vcl_backend_error {
     set beresp.http.Content-Type = "text/html; charset=utf-8";
     set beresp.http.Retry-After = "5";
     synthetic( {"<!DOCTYPE html>
 <html>
   <head>
     <title>"} + beresp.status + " " + beresp.reason + {"</title>
     <meta http-equiv="refresh" content="1">
   </head>
   <body>
     <h1>Error "} + beresp.status + " " + beresp.reason + {"</h1>
     <p>"} + beresp.reason + {"</p>
     <h3>Guru Meditation:</h3>
     <p>XID: "} + bereq.xid + {"</p>
     <hr>
     <p>Totally not a Varnish cache server errror</p>
   </body>
 </html>
 "} );
     return (deliver);
 }
