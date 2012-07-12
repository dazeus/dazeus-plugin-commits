#!/usr/bin/perl
use strict;
use warnings;
use DaZeus;
use IO::Socket::INET;
# We need JSON::PP as loose interpreting is necessary to have newlines in
# JSON strings (which is normal in the commit body)
use JSON -support_by_pp;

my $short = 0;
if(@ARGV > 1 && $ARGV[0] eq "--short") {
	$short = 1;
	shift @ARGV;
}

my ($sourcehost, $listenport, $socket, $network, $channel) = @ARGV;
if(!$channel) {
	die "Usage: $0 [--short] sourcehost listenport socket network channel\n";
}

my $dazeus = DaZeus->connect($socket);
my $joined = 0;
foreach(@{$dazeus->networks()}) {
	if($_ eq $network) {
		$joined = 1;
		last;
	}
}
if(!$joined) {
	warn "Chosen network doesn't seem to be known in DaZeus...\n";
	warn "Known networks: " . join(', ', @{$dazeus->networks()}) . "\n";
	exit;
}

print "Sending to $channel on network $network.\n";

my $listen = IO::Socket::INET->new(
	Proto => "udp",
	Type => SOCK_DGRAM,
#/	LocalAddr => "::",
	LocalPort => $listenport,
	Blocking => 1,
);

if(!$listen) {
	die $!;
}

my $data;
my $json = JSON->new->loose;
while(my $sender = $listen->recv($data, 1024)) {
	my ($port, $ipaddr) = sockaddr_in($sender);
	my $ip_readable = join ".", unpack("C4", $ipaddr);
	my $hishost = gethostbyaddr($ipaddr, AF_INET);
	if($ip_readable ne $sourcehost && $hishost ne $sourcehost) {
		warn "Client $ip_readable [$hishost] sent something, but not equal to $sourcehost; ignoring\n";
		next;
	}

	eval {
		$data = $json->decode($data);
	};
	if($@) {
		warn "Did not receive valid JSON from $ip_readable [$hishost]:\n";
		warn "$data\n";
		next;
	}

	my $id = $data->{'id'};
	my $rev = substr($id, 0, 6);
	my $fullauthor = $data->{'author'};
	my ($author, $email) = $fullauthor =~ /^([^<]+) <(.+)>$/;
	my $message = $data->{'message'};
	my $ref = $data->{'ref'};
	next if($ref !~ m#^refs/heads/(.+)$#);
	$ref = $1;
	my $branchdescr = $ref eq "master" ? "" : " (branch '$ref')";
	# TODO: find a common directory for all changed files
	my @fileschanged = @{$data->{'changed'}};
	my $filechanged = @fileschanged == 1 ? $fileschanged[0] : "(" . scalar(@fileschanged) . " files)";
	my $summary = $data->{'message'};
	my @shortlog = split /\n/, $data->{'body'};
	@shortlog = grep { length > 0 } @shortlog;
	@shortlog = @shortlog[0..2] if(@shortlog > 3);
	my $shortlog = join "\n", @shortlog;

	if($short) {
		$data = "$author r${rev}${branchdescr} - $filechanged - $summary";
	} else {
		$data = "$fullauthor r${rev}${branchdescr} - $filechanged:\n";
		$data .= "$summary\n";
		$data .= $shortlog;
	}

	print "$data\n-----\n";

	eval {
		$dazeus->message($network, $channel, $data);
	};
	if( $@ )
	{
		warn "Error executing message(): $@\n";
	}
}

1;
