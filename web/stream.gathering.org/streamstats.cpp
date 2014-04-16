#include <stdio.h>
#include <string.h>
#include <map>
#include <set>
#include <string>
#include <vector>
#include <stdlib.h>

using namespace std;

map<string, string> port_desc = {
	{ "3013", "main (3013)" },
	{ "3014", "main-sd (3014)" },
	{ "3015", "webcam (3015)" },
	{ "3016", "webcam-south (3016)" },
	{ "3017", "webcam-south-transcode (3017)" },
	{ "3018", "webcam-fisheye (3018)" },
	{ "5013", "main-transcode (5013)" },
	{ "5015", "webcam-transcode (5015)" },
};

struct Spec {
	set<string> incl;
	bool compare;
};

Spec parse_spec(const string &spec)
{
	Spec ret;
	ret.compare = false;

	if (spec == "compare") {
		ret.compare = true;
		return ret;
	}
	if (spec == "dontcare") {
		return ret;
	}

	const char *ptr = spec.c_str();
	if (strncmp(ptr, "compare:", 8) == 0) {
		ptr += 8;
		ret.compare = true;
	}

	for ( ;; ) {
		const char *end = strchr(ptr, ',');
		if (end == NULL) {
			ret.incl.insert(ptr);
			break;
		} else {
			ret.incl.insert(string(ptr, end));
			ptr = end + 1;
		}
	}

	return ret;
}

bool filter(const string &entry, const Spec &spec)
{
	if (spec.incl.empty()) {
		return false;
	}
	return spec.incl.count(entry) == 0;
}

vector<string> get_stream_id(const string& port, const string &proto, const string &audience,
                             const Spec& port_spec, const Spec &proto_spec, const Spec &audience_spec)
{
	vector<string> keys;
	if (port_spec.compare) {
		if (port_desc.count(port)) {
			keys.push_back(port_desc[port]);
		} else {
			char buf[256];
			sprintf(buf, "___%s___", port.c_str());
			keys.push_back(buf);
		}
	}
	if (proto_spec.compare) {
		keys.push_back(proto);
	}
	if (audience_spec.compare) {
		keys.push_back(audience);
	}
	return keys;
}

string get_stream_desc(const vector<string> &stream_id)
{
	string ret;
	for (int i = 0; i < stream_id.size(); ++i) {
		if (i != 0) {
			ret += ",";
		}
		ret += stream_id[i];
	}
	return ret;
}

int main(int argc, char **argv)
{
	Spec port_spec = parse_spec(argv[2]);
	Spec proto_spec = parse_spec(argv[3]);
	Spec audience_spec = parse_spec(argv[4]);
		
	map<string, map<vector<string>, int> > lines;
	map<vector<string>, int> stream_ids;
	vector<string> stream_descs;

	// Parse the log.
	FILE *fp;
	if (strcmp(argv[1], "-") == 0) {
		fp = stdin;
	} else {
		fp = fopen(argv[1], "r");
	}
	while (!feof(fp)) {
		char buf[1024];
		fgets(buf, 1024, fp);

		if (buf == NULL) {
			break;
		}
		char *ptr = strchr(buf, '\n');
		if (ptr != NULL) {
			*ptr = 0;
		}

		char *date = strtok(buf, " ");
		char *port = strtok(NULL, " ");
		char *proto = strtok(NULL, " ");
		char *audience = strtok(NULL, " ");
		char *count = strtok(NULL, " ");
	
		if (date == NULL || port == NULL || proto == NULL || audience == NULL || count == NULL) {
			continue;
		}	

		if (filter(port, port_spec)) {
			continue;
		}
		if (filter(proto, proto_spec)) {
			continue;
		}
		if (filter(audience, audience_spec)) {
			continue;
		}

		vector<string> stream_id = get_stream_id(port, proto, audience, port_spec, proto_spec, audience_spec);
		if (stream_ids.count(stream_id) == 0) {
			int stream_id_num = stream_ids.size();
			stream_ids.insert(make_pair(stream_id, stream_id_num));
			stream_descs.push_back(get_stream_desc(stream_id));
		}
		lines[date][stream_id] += atoi(count);
	}
	fclose(fp);

	// Output.
	char *data_file = tempnam(NULL, "data");
	FILE *datafp = fopen(data_file, "w");
	if (datafp == NULL) {
		perror(data_file);
		exit(1);
	}

	vector<int> cols(stream_ids.size());
	for (auto& it : lines) {
		const string& date = it.first;
	
		for (const auto& it2 : stream_ids) {
			const vector<string>& stream_id = it2.first;
			int stream_id_num = it2.second;

			cols[stream_id_num] = it.second[stream_id];  // note: might zero-initialize
		}
		fprintf(datafp, "%s", date.c_str());
		for (int i = 0; i < cols.size(); ++i) {
			fprintf(datafp, " %d", cols[i]);
		}
		fprintf(datafp, "\n");
	}
	fclose(datafp);

	// Make gnuplot script.
	char *plot_file = tempnam(NULL, "plot");
	FILE *plotfp = fopen(plot_file, "w");
	if (plotfp == NULL) {
		perror(plot_file);
		exit(1);
	}

	fprintf(plotfp, "set terminal png\n");
	fprintf(plotfp, "set xdata time\n");
	fprintf(plotfp, "set timefmt \"20%%y-%%m-%%d-%%H:%%M:%%S\"\n");
	fprintf(plotfp, "set xtics axis \"2000-00-00-01:00:00\"\n");
	fprintf(plotfp, "set format x \"%%H\"\n");

	fprintf(plotfp, "plot");
	for (int i = 0; i < cols.size(); ++i) {
		if (i == 0) {
			fprintf(plotfp, " ");
		} else {
			fprintf(plotfp, ",");
		}
		fprintf(plotfp, "\"%s\" using 1:%d title \"%s\" with lines", data_file, i + 2, stream_descs[i].c_str());
	}
	fprintf(plotfp, "\n");

	fclose(plotfp);

	char buf[1024];
	sprintf(buf, "gnuplot < %s", plot_file);
	system(buf);
}
