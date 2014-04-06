// Find optimal assignment of access switches using min-cost max-flow.
// About three times as fast as the old DP+heuristics-based solution
// (<2ms for planning TG), and can deal with less regular cost metrics.
//
// Given D distro switches and N access switches, complexity is approx. O(dn³)
// (runs n iterations, each iteration is O(VE), V is O(n), E is O(dn))).
//
// g++ -std=gnu++0x -Wall -g -O2 -DOUTPUT_FILES=1 -o planning planning.cc && ./planning -6 11 22 -26 35

#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <limits.h>
#include <assert.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <vector>
#include <map>
#include <algorithm>
#include <string>
#include <utility>
#include <queue>

#define NUM_DISTRO 5
#define SWITCHES_PER_ROW 4
#define PORTS_PER_DISTRO 38

#define TRUNCATE_METRIC 1
#define EXTENSION_COST 70
#define HORIZ_GAP_COST 100

#define FIRST_SUBNET_ADDRESS "151.216.1.0"
#define SUBNET_SIZE 26

#define _INF 99999

struct Switch {
	unsigned row, num;

	Switch(unsigned row, unsigned num) : row(row), num(num) {}
};

struct Inventory {
	Inventory() : num_10m(0), num_30m(0), num_50m(0), extensions(0), horiz_gap_crossings(0) {}

	Inventory& operator+= (const Inventory& other)
	{
		this->num_10m += other.num_10m;
		this->num_30m += other.num_30m;
		this->num_50m += other.num_50m;
		this->extensions += other.extensions;
		this->horiz_gap_crossings += other.horiz_gap_crossings;
		return *this;
	}

	std::string to_string() const
	{
		if (num_10m >= _INF) {
			return "XXXXX";
		}

		std::string ret;
		Inventory copy = *this;
		while (copy.num_50m-- > 0) {
			if (!ret.empty()) {
				ret += '+';
			}
			ret += "50";
		}
		while (copy.num_30m-- > 0) {
			if (!ret.empty()) {
				ret += '+';
			}
			ret += "30";
		}
		while (copy.num_10m-- > 0) {
			if (!ret.empty()) {
				ret += '+';
			}
			ret += "10";
		}
		return ret;
	}

	unsigned num_10m, num_30m, num_50m;
	unsigned extensions, horiz_gap_crossings;
};

// Data structures for flow algorithm.
struct Node;
struct Edge {
	Node *to;
	Edge *reverse;  // Edge in opposite direction.

	int capacity, flow;
	int cost;
};
struct Node {
	std::vector<Edge *> edges;

	// For debugging.
	char name[16];

	// Used in Dijkstra search.
	int cost_from_source;
	bool seen;
	Edge *prev_edge;
};


const unsigned horiz_cost[SWITCHES_PER_ROW] = {
	216, 72, 72, 216  // Gap costs are added separately.
};

class Planner {
 private:
	int distro_placements[NUM_DISTRO];
	std::vector<Switch> switches;
	std::map<unsigned, unsigned> num_ports_used;
	std::string *log_buf;

	unsigned find_distance(Switch from_where, unsigned distro);
	unsigned find_slack(Inventory inventory, unsigned distance);
	unsigned find_cost(Switch from_where, unsigned distro);
	Inventory find_inventory(Switch from_where, unsigned distro);
	void logprintf(const char *str, ...);
	void init_switches();

 public:
	Planner() : log_buf(NULL) {}
	void set_log_buf(std::string *log_buf) { this->log_buf = log_buf; }
	int do_work(int distro_placements[NUM_DISTRO]);
};

unsigned Planner::find_distance(Switch from_where, unsigned distro)
{
	const int dp = abs(distro_placements[distro]);

	// 3.7m from row to row (2.5m gap + 1.2m boards).
	unsigned base_cost = 37 * abs(from_where.row - dp) +
		horiz_cost[from_where.num];

	if ((distro_placements[distro] >= 0) == (from_where.num >= 2)) {
		// 5.0m horizontal gap.
		base_cost += 50;
	}
	
	// 4m, 5m, 4m gaps (1.5m, 2.5m, 1.5m extra).
	if ((from_where.row <= 5) == (dp >= 6))
		base_cost += 15;
	if ((from_where.row <= 13) == (dp >= 14))
		base_cost += 15;
	if ((from_where.row <= 21) == (dp >= 22))
		base_cost += 25;
	if ((from_where.row <= 29) == (dp >= 30))
		base_cost += 15;

	// Add 5m slack.
	return base_cost + 50;
}
	
Inventory Planner::find_inventory(Switch from_where, unsigned distro)
{
	unsigned distance = find_distance(from_where, distro);

	Inventory inv;
	if (distance <= 100) {
		inv.num_10m = 1;
	} else if (distance <= 200) {
		inv.num_10m = 2;
		inv.extensions = 1;
	} else if (distance <= 300) {
		inv.num_30m = 1;
	} else if (distance <= 400) {
		inv.num_10m = 1;
		inv.num_30m = 1;
		inv.extensions = 1;
	} else if (distance <= 500) {
		inv.num_50m = 1;
	} else if (distance <= 600) {
		inv.num_10m = 1;
		inv.num_50m = 1;
		inv.extensions = 1;
	} else if (distance <= 800) {
		inv.num_30m = 1;
		inv.num_50m = 1;
		inv.extensions = 1;
	} else if (distance <= 1000) {
		inv.num_50m = 2;
		inv.extensions = 1;
	} else {
		inv.num_10m = _INF;
	}

	if ((distro_placements[distro] >= 0) == (from_where.num >= 2)) {
		inv.horiz_gap_crossings = 1;
	}

	return inv;
}

unsigned Planner::find_slack(Inventory inventory, unsigned distance)
{
	return 100 * inventory.num_10m + 300 * inventory.num_30m + 500 * inventory.num_50m - distance;
}

unsigned Planner::find_cost(Switch from_where, unsigned distro)
{
	Inventory inv = find_inventory(from_where, distro);
	unsigned cost;

#if TRUNCATE_METRIC
	cost = 100 * inv.num_10m + 300 * inv.num_30m + 500 * inv.num_50m + EXTENSION_COST * inv.extensions;
	// cost = find_slack(inv, distance);
#else
	cost = find_distance(from_where, distro);
	// cost = ((distance + 90) / 100) * 100;
#endif

	// We really, really do not want to cross the gap on the north side.
	if (from_where.row <= 30) {
		cost += _INF * inv.horiz_gap_crossings;
	} else {
		cost += HORIZ_GAP_COST * inv.horiz_gap_crossings;
	}

	return cost;
}

void Planner::logprintf(const char *fmt, ...)
{
	if (log_buf == NULL) {
		return;
	}

	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);

	log_buf->append(buf);
}

std::string distro_name(unsigned distro)
{
	char buf[16];
	sprintf(buf, "distro%d", distro + 1);
	return buf;
}

std::string port_name(unsigned distro, unsigned portnum)
{
	char buf[16];
	int distros[] = { 1, 2, 5, 6 };
	sprintf(buf, "Gi%u/%u", distros[portnum / 48], (portnum % 48) + 1);
	return buf;
}

void Planner::init_switches()
{
	switches.clear();
	for (unsigned i = 1; i <= 39; ++i) {
		if (!(i >= 1 && i <= 5)) {
			switches.push_back(Switch(i, 0));
			switches.push_back(Switch(i, 1));
		}
		if (!(i >= 14 && i <= 21) &&
		    !(i >= 39)) {
			switches.push_back(Switch(i, 2));
			switches.push_back(Switch(i, 3));
		}
	}
}

void add_edge(Node *from, Node *to, int capacity, int cost, std::vector<Edge> *edges)
{
	assert(edges->size() + 2 <= edges->capacity());
	edges->resize(edges->size() + 2);

	Edge *e1 = &edges->at(edges->size() - 2);
	Edge *e2 = &edges->at(edges->size() - 1);

	e1->to = to;
	e1->capacity = capacity;
	e1->flow = 0;
	e1->cost = cost;
	e1->reverse = e2;
	from->edges.push_back(e1);

	e2->to = from;
	e2->capacity = 0;
	e2->flow = 0;
	e2->cost = -cost;
	e2->reverse = e1;
	to->edges.push_back(e2);
}
		
int Planner::do_work(int distro_placements[NUM_DISTRO])
{
	memcpy(this->distro_placements, distro_placements, sizeof(distro_placements[0]) * NUM_DISTRO);

	num_ports_used.clear();

#if OUTPUT_FILES
	FILE *patchlist = fopen("patchlist.txt", "w");
	FILE *switchlist = fopen("switches.txt", "w");
#endif
	Inventory total_inv;
	unsigned total_cost = 0, total_slack = 0;

	init_switches();

	logprintf("Finding optimal layout for %u switches\n", switches.size());

	// Min-cost max-flow in a graph that looks something like this
	// (ie., all distros connect to all access switches):
	//
	//         ---- D1 \---/-- A1 --
	//        /         \ /         \          .
	// source ----- D2 --X---- A2 --- sink
	//        \         / \         /
 	//         ---- D3 /---\-- A3 -/
	//
	// Capacity from source to distro is 48 (or whatever), cost is 0.
	// Capacity from distro to access is 1, cost is cable length + penalties.
	// Capacity from access to sink is 1, cost is 0.
	Node source_node, sink_node;
	Node distro_nodes[NUM_DISTRO];
	std::vector<Node> switch_nodes;
	std::vector<Edge> edges;
	switch_nodes.resize(switches.size());
	edges.reserve(switches.size() * NUM_DISTRO * 2 + 16);

	for (unsigned i = 0; i < NUM_DISTRO; ++i) {
		add_edge(&source_node, &distro_nodes[i], PORTS_PER_DISTRO, 0, &edges);
	}
	for (unsigned i = 0; i < NUM_DISTRO; ++i) {
		for (unsigned j = 0; j < switches.size(); ++j) {
			int cost = find_cost(switches[j], i);
			if (cost >= _INF) {
				continue;
			}
			add_edge(&distro_nodes[i], &switch_nodes[j], 1, cost, &edges);
		}
	}
	for (unsigned i = 0; i < switches.size(); ++i) {
		add_edge(&switch_nodes[i], &sink_node, 1, 0, &edges);
	}
	
	std::vector<Node*> all_nodes;
	all_nodes.push_back(&source_node);
	strcpy(source_node.name, "source");

	all_nodes.push_back(&sink_node);
	strcpy(sink_node.name, "sink");

	for (unsigned i = 0; i < NUM_DISTRO; ++i) {
		all_nodes.push_back(&distro_nodes[i]);
		sprintf(distro_nodes[i].name, "distro%d", i);
	}
	for (unsigned i = 0; i < switches.size(); ++i) {
		all_nodes.push_back(&switch_nodes[i]);
		sprintf(switch_nodes[i].name, "switch%d", i);
	}

	// We use the successive shortest path algorithm, using a primitive Dijkstra
	// (not heap-based, so O(VE)) for search.
	int num_paths = 0;
	for ( ;; ) {
		// Reset Dijkstra state.
		for (unsigned i = 0; i < all_nodes.size(); ++i) {
			Node *n = all_nodes[i];
			n->cost_from_source = _INF;
			n->seen = false;
			n->prev_edge = NULL;
		}
		source_node.cost_from_source = 0;

		for (unsigned i = 0; i < switches.size(); ++i) {
			Node *cheapest_unseen_node = NULL;
			for (unsigned i = 0; i < all_nodes.size(); ++i) {
				Node *n = all_nodes[i];
				if (n->seen || n->cost_from_source >= _INF) {
					continue;
				}
				if (cheapest_unseen_node == NULL ||
				    n->cost_from_source < cheapest_unseen_node->cost_from_source) {
					cheapest_unseen_node = n;
				}
			}
			if (cheapest_unseen_node == NULL) {
				// Oops, no usable path.
				goto end;
			}
			if (cheapest_unseen_node == &sink_node) {
				// Yay, we found a path to the sink.
				break;
			}

			cheapest_unseen_node->seen = true;

			// See if any of the edges out from this are feasible.
			for (unsigned i = 0; i < cheapest_unseen_node->edges.size(); ++i) {
				Edge *e = cheapest_unseen_node->edges[i];
				if (e->flow + 1 > e->capacity || e->reverse->flow - 1 > e->reverse->capacity) {
					// Not feasible.
					continue;
				}
				if (e->to->cost_from_source <= cheapest_unseen_node->cost_from_source + e->cost) {
					// Already seen through a better path.
					continue;
				}
				e->to->seen = false;
				e->to->prev_edge = e;
				e->to->cost_from_source = cheapest_unseen_node->cost_from_source + e->cost;
			}
		}

		// Increase flow along the path, moving backwards towards the source.
		Node *n = &sink_node;
		for ( ;; ) {
			if (n->prev_edge == NULL) {
				break;
			}

			n->prev_edge->flow += 1;
			n->prev_edge->reverse->flow -= 1;

			n = n->prev_edge->reverse->to;
		}
		++num_paths;
	}

end:
	logprintf("Augmented using %d paths.\n", num_paths, (unsigned)switches.size());
	int last_row = 0, last_num = -1;
#if OUTPUT_FILES
	in_addr_t subnet_address = inet_addr(FIRST_SUBNET_ADDRESS);
#endif
	for (unsigned i = 0; i < switches.size(); ++i) {
		// Figure out which distro this switch was connected to.
		int distro = -1;
		for (unsigned j = 0; j < NUM_DISTRO; ++j) {
			Edge *flow_edge = NULL;
			for (unsigned k = 0; k < distro_nodes[j].edges.size(); ++k) {
				Edge *e = distro_nodes[j].edges[k];
				if (e->to == &switch_nodes[i]) {
					flow_edge = e;
					break;
				}
			}
			if (flow_edge != NULL && flow_edge->flow > 0) {
				distro = j;
				break;
			}
		}

		if (i == 0 || switches[i].row != switches[i - 1].row) {
			if (last_row == 13 || last_row == 21 || last_row == 29) {
				logprintf("\n");
			}
			logprintf("\n[31;22m%2u (%2u-%2u)    ", switches[i].row, switches[i].row * 2 - 1, switches[i].row * 2 + 0);
			last_num = -1;
		}
		for (unsigned j = last_num; j + 1 < switches[i].num; ++j) {
			logprintf("%19s", "");
		}

		char distro_marker_left[16] = " ";
		char distro_marker_right[16] = " ";
		if (switches[i].num == 1) {
			for (int d = 0; d < NUM_DISTRO; ++d) {
				if (int(switches[i].row) == distro_placements[d]) {
					sprintf(distro_marker_left, "[%u;1m*", d + 32);
				}
				if (int(switches[i].row) == -distro_placements[d]) {
					sprintf(distro_marker_right, "[%u;1m*", d + 32);
				}
			}
		}

		int this_distance;
		Inventory this_inv;
		if (distro == -1) {
			this_distance = _INF;
			this_inv.num_10m = _INF;
			logprintf("[%u;22m- ", distro + 32);
		} else {
			this_distance = find_distance(switches[i], distro);
			this_inv = find_inventory(switches[i], distro);
			total_cost += find_cost(switches[i], distro);
			logprintf("[%u;22m%u ", distro + 32, distro);
		}
	
#if TRUNCATE_METRIC
		logprintf("(%-5s) (%3.1f)%s %s", this_inv.to_string().c_str(), this_distance / 10.0, distro_marker_left, distro_marker_right);
#else
		logprintf("(%3.1f)%s %s", this_distance / 10.0, distro_marker_left, distro_marker_right);
#endif
		total_slack += find_slack(this_inv, this_distance);
		total_inv += this_inv;
				
		last_row = switches[i].row;
		last_num = switches[i].num;
			
#if OUTPUT_FILES
		int port_num = num_ports_used[distro]++;
		fprintf(patchlist, "e%u-%u %s %s %s %s %s\n",
			last_row * 2 - 1, last_num + 1,
			distro_name(distro).c_str(),
			port_name(distro, port_num).c_str(),
			port_name(distro, port_num + 48).c_str(),
			port_name(distro, port_num + 96).c_str(),
			port_name(distro, port_num + 144).c_str());

		in_addr subnet_addr4;
		subnet_addr4.s_addr = subnet_address;
		fprintf(switchlist, "%s %u e%u-%u x.x.x.x\n",
			inet_ntoa(subnet_addr4), SUBNET_SIZE, last_row * 2 - 1, last_num + 1);
		subnet_address = htonl(ntohl(subnet_address) + (1ULL << (32 - SUBNET_SIZE)));
#endif
	}
#if OUTPUT_FILES
	fclose(patchlist);
	fclose(switchlist);
#endif
	logprintf("\n");
	logprintf("[%u;22m\n", 37);

#if TRUNCATE_METRIC
	logprintf("\n");
	logprintf("10m: %3u\n", total_inv.num_10m);
	logprintf("30m: %3u\n", total_inv.num_30m);
	logprintf("50m: %3u\n", total_inv.num_50m);
	logprintf("Extensions: %u\n", total_inv.extensions);
	logprintf("Horizontal gap crossings: %u\n", total_inv.horiz_gap_crossings);
	logprintf("\n");

	if (total_inv.num_10m >= _INF) {
		logprintf("Total cost: Impossible\n");
		return INT_MAX;
	}
	int total_cable = 100 * total_inv.num_10m + 300 * total_inv.num_30m + 500 * total_inv.num_50m;
#else
	// Not correct unless EXTENSION_COST = HORIZ_GAP_COST = 0, but okay.
	int total_cable = total_cost;
#endif

	logprintf("Total cable: %.1fm (cost = %.1fm)\n", total_cable / 10.0, total_cost / 10.0);
	logprintf("Total slack: %.1fm (%.2f%%)\n", total_slack / 10.0, 100.0 * double(total_slack) / double(total_cable));

	for (int i = 0; i < NUM_DISTRO; ++i) {
		Edge *e = source_node.edges[i];
		logprintf("Remaining ports on distro %d: %d\n", i + 1, e->capacity - e->flow);
	}
	return total_cost;
}

int main(int argc, char **argv)
{
	int distro_placements[NUM_DISTRO];
	for (int i = 0; i < NUM_DISTRO; ++i) {
		distro_placements[i] = atoi(argv[i + 1]);
	}

	std::string log;
	Planner p;
	log.clear();
	p.set_log_buf(&log);
	(void)p.do_work(distro_placements);
	printf("%s\n", log.c_str());
	return 0;
}
