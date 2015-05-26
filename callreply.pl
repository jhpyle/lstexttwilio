#!/usr/bin/perl
use strict;
use Carp;
use warnings;
use CGI qw/:standard/;
my $q = CGI->new();

print $q->header(-type => 'application/xml', -expires => 'now');
my $string = <<'EOF';
<?xml version="1.0" encoding="UTF-8" ?>
<Response>
  <Play>http://docket.philalegal.org/auto-reply.mp3</Play>
</Response>
EOF
print $string;
exit;
