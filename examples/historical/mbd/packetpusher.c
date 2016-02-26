#include <stdio.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <stdint.h>
#include <arpa/inet.h>

char encoded_pkt[4096], workspace[4096];
unsigned char pkt[2048];

typedef uint32_t u_int32_t;

u_int32_t checksum(unsigned char *buf, unsigned nbytes, u_int32_t sum)
{
	int i;
	/* Checksum all the pairs of bytes first... */
	for (i = 0; i < (nbytes & ~1U); i += 2) {
		sum += (u_int16_t)ntohs(*((u_int16_t *)(buf + i)));
		if (sum > 0xFFFF)
			sum -= 0xFFFF;
	}

	/*
	 * If there's a single byte left over, checksum it, too.
	 * Network byte order is big-endian, so the remaining byte is
	 * the high byte.
	 */

	if (i < nbytes) {
		sum += buf[i] << 8;
		if (sum > 0xFFFF)
			sum -= 0xFFFF;
	}

	return (sum);
}

u_int32_t wrapsum(u_int32_t sum)
{
	sum = ~sum & 0xFFFF;
	return (htons(sum));
}

int main(int argc, char **argv)
{
	int sock = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
	if (sock == -1) {
		perror("socket");
		exit(1);
	}

	for ( ;; ) {
		int num_pkts;
		int ret = scanf("%d %s", &num_pkts, encoded_pkt);
		if (ret != 2) {
			fprintf(stderr, "error parsing! ret=%d\n", ret);
			exit(1);
		}
		if ((strlen(encoded_pkt) % 2) != 0) {
			fprintf(stderr, "hex packet has odd length\n");
			exit(1);
		}

		// de-hex packet
		for (int i = 0; i < strlen(encoded_pkt); i += 2) {
			char c[3];
			c[0] = encoded_pkt[i];
			c[1] = encoded_pkt[i + 1];
			c[2] = 0;
			int h = strtol(c, NULL, 16);
			pkt[i / 2] = h;
		}

		int datalen = strlen(encoded_pkt) / 2;

		for (int i = 0; i < num_pkts; ++i) {
			char from_ip[256], to_ip[256];
			int sport, dport;
			if (scanf("%s %d %s %d", from_ip, &sport, to_ip, &dport) != 4) {
				fprintf(stderr, "error parsing packet %d!\n", i);
				exit(1);
			}

			// IP header
			struct iphdr *ip = (struct iphdr *)workspace;
			ip->version = 4;
			ip->ihl = 5;
			ip->tos = 0;
			ip->tot_len = htons(datalen + sizeof(struct iphdr) + sizeof(struct udphdr));
			ip->id = 0;
			ip->frag_off = 0;
			ip->ttl = 64;
			ip->protocol = 17;  // UDP
			ip->saddr = inet_addr(from_ip);
			ip->daddr = inet_addr(to_ip);
			ip->check = 0;
			ip->check = wrapsum(checksum((unsigned char *)ip, sizeof(*ip), 0));

			// UDP header
			struct udphdr *udp = (struct udphdr *)(workspace + sizeof(struct iphdr));
			udp->source = htons(sport);
			udp->dest = htons(dport);
			udp->len = htons(datalen + sizeof(struct udphdr));
			udp->check = 0;

			int sum = checksum((unsigned char *)&ip->saddr, 2 * sizeof(ip->saddr), IPPROTO_UDP + ntohs(udp->len));
			sum = checksum((unsigned char *)pkt, datalen, sum);
			sum = checksum((unsigned char *)udp, sizeof(*udp), sum);
			udp->check = wrapsum(sum);

			// Data
			memcpy(workspace + sizeof(struct iphdr) + sizeof(struct udphdr),
			       pkt, datalen);

			// Send out the packet physically
			struct sockaddr_in to;
			to.sin_family = AF_INET;
			to.sin_addr.s_addr = inet_addr(to_ip);
			to.sin_port = htons(dport);

			sendto(sock, workspace, ntohs(ip->tot_len), 0, (struct sockaddr *)&to, sizeof(to));
		}
	}
}
