import base64
import json
import os
import re
import urllib.parse
import urllib.request

GONDUL_USERNAME = os.getenv("GONDUL_USERNAME", "")
GONDUL_PASSWORD = os.getenv("GONDUL_PASSWORD", "")
GONDUL_API = os.getenv("GONDUL_API", "https://gondul.tg23.gathering.org/api")
GONDUL_SWITCHES_ENDPOINT = os.getenv(
    "GONDUL_SWITCHES_ENDPOINT", "/public/switches")


def _generate_credentials(username, password):
    return base64.standard_b64encode(
        (username + ":" + password)
        .encode("utf-8")).decode("utf-8")


def _do_switches_request(
        api=GONDUL_API,
        endpoint=GONDUL_SWITCHES_ENDPOINT,
        credentials=_generate_credentials(GONDUL_USERNAME, GONDUL_PASSWORD)):
    switches_url = api + endpoint

    # Build request
    request = urllib.request.Request(switches_url)
    request.add_header("Authorization", "Basic " + credentials)
    resp = urllib.request.urlopen(request, timeout=5)
    assert resp.status == 200, "HTTP return was not 200 OK"

    # Read response
    body = resp.read().decode("utf-8")
    data = json.loads(body)
    assert "switches" in data, "Missing switches object from HTTP response"

    switches = data.get("switches")
    print("Found {} switches in Gondul".format(len(switches)))
    return switches


def _match_switches(switches, match="^e([0-9]+-[0-9]+)"):
    pattern = re.compile(match)

    included_switches = []
    for switch in switches:
        include = re.search(pattern, switch)
        if include:
            included_switches.append(switch)

    print("'{}' matches {} switches.".format(match, len(included_switches)))
    return included_switches


def _sort_switches(switches):
    # The lambda returns two values to compare on;
    # * The switch number (e77-4) - picks out the number 77
    # * The number of the switch in relation to other switches on the same row
    # E.g. "e77-4" will return 4
    return sorted(switches, key=lambda x: (int(x[1:].split("-")[0]), x.split("-")[1]))


def fetch_gondul_switches(api=None, endpoint=None, username=None, password=None, match="^e([0-9]+-[0-9]+)"):
    # Use provided arg instead of environment variable if defined.
    _api = api if api is not None else GONDUL_API
    _endpoint = endpoint if endpoint is not None else GONDUL_SWITCHES_ENDPOINT
    _username = username if username is not None else GONDUL_USERNAME
    _password = password if password is not None else GONDUL_PASSWORD
    credentials = _generate_credentials(_username, _password)

    return _sort_switches(
        _match_switches(
            _do_switches_request(
                api=_api, endpoint=_endpoint, credentials=credentials),
            match=match))
