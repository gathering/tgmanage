// gcc -O2 -o derspan derspan.c -lpcap -std=gnu99 -Wall

#include <pcap.h>
#include <stdlib.h>
#include <netinet/ip.h>
#include <stdint.h>
#include <stdio.h>

int rawsock;

void my_callback(u_char *user, const struct pcap_pkthdr *h, const u_char *bytes)
{
	int len = h->caplen;
	if (len < 40) {
		//printf("skipped short packet\n");
		return;
	}
	if (bytes[14] != 0x88 || bytes[15] != 0xbe) {
		//printf("skipped non-ethernet packet\n");
		return;
	}
	if (bytes[36] != 0x08 || bytes[37] != 0x00) {
		//printf("skipped non-IPv4 packet\n");
		return;
	}

	struct sockaddr_in self;
	self.sin_family = AF_INET;
	self.sin_addr.s_addr = htonl(0x7f000001);  // localhost
	self.sin_port = htons(1337);

	sendto(rawsock, bytes + 38, len - 38, 0, (struct sockaddr *)&self, sizeof(self));
}

int main(int argc, char **argv)
{
	rawsock = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
	if (rawsock == -1) {
		perror("socket");
		exit(0);
	}

	pcap_t *pcap = pcap_open_live(argv[1], 1500, 1, 1000, NULL);
	pcap_activate(pcap);
	pcap_loop(pcap, -1, my_callback, NULL);
	return 0;
}

