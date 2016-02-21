# vim: ts=8:expandtab:sw=4:softtabstop=4

# Magi.
vcl 4.0;

# Mer magi.
backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

# Sort magi.
sub vcl_recv {
    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE") {
        # Vi hater alt som er gøy.
        return (synth(418,"LOLOLOL"));
    }

    # Hardcoded for testing
    set req.http.host = "nms.tg16.gathering.org"; 

    if (req.method != "GET" && req.method != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pass);
    }

    # Brukes ikke. Cookies er for nubs.
    unset req.http.Cookie;

    # Tvinges gjennom for å cache med authorization-skrot.
    return (hash);
}

# Rosa magi
sub vcl_hash {
    # Wheee. Legg til authorization-headeren i hashen.
    hash_data(req.http.authorization);
}

# Mauve magi. Hva nå enn det er.
# Dette er WIP - Skal flyttes til backend
sub vcl_backend_response {
    if (beresp.status == 200) {
        set beresp.ttl = 2s;
    } else {
        # Vi cacher feilmeldinger, fordi vi er kule.
        set beresp.ttl = 1s;
    }

    if(bereq.url ~ "port-state.pl" && beresp.status == 200) {
        set beresp.ttl = 1s;
    }
    if (beresp.status == 200 && bereq.url ~ "now=") {
        # Historisk data kan vi cache cirka evig
        set beresp.ttl = 60m;
    }
}
