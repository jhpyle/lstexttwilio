#! /usr/bin/perl -w

use strict;
use warnings;
use Carp;
use MIME::Parser;
use File::Temp qw/ tempdir /;
use IO::Dir;
use IO::All;
use Data::Dumper;
use Email::Send;
use Email::Simple::Creator;
use Email::MIME::Creator;
use Email::MIME::CreateHTML;
use LWP::UserAgent;
use DBI;

my $dir = tempdir( CLEANUP => 0 );
my $parser = new MIME::Parser;
$parser->output_under($dir);
my $entity = $parser->parse(\*STDIN);
#$entity->dump_skeleton;
my $head = $parser->last_head;
#print "From is " . $head->get('From') . "\n";
#print "To is " . $head->get('To') . "\n";
#print "Subject is " . $head->get('Subject') . "\n";
#print "Check out $dir\n";
#exit;
my $from = $head->get('From');
exit unless ($from && $from =~ /jpyle\@philalegal.org/);
$from =~ s/\n//g;
my $subject = $head->get('Subject');
$subject =~ s/\n//g;
my $phone_number;
if ($subject && $subject =~ /Message from ([0-9\+]+)/){
  $phone_number = $1;
  $phone_number =~ s/^\+*1*//;
}

my @caseinfo;
if ($phone_number){
  my $phone;
  my (@conditions, @parameters);
  my $ldref = DBI->connect('dbi:Pg:dbname=pla_live;host=192.168.200.204', 'psti', 'secretsecret', {AutoCommit => 1}) or croak DBI->errstr;
  my $initial = "select person.id as personid, matter.id as matterid, matter.identification_number, matter.date_open, matter.close_date, lookup_legal_problem_code.name as problem_code, person.first, person.last, person.addr1, person.city, person.state, person.zip, person.phone_business, person.phone_home, person.phone_mobile, person.phone_fax, person.phone_other, lookup_case_disposition.name as disposition, userperson.first as sfname, userperson.last as slname, userperson.email as semail from person left outer join matter on (matter.person_id=person.id) left outer join lookup_case_disposition on (matter.case_disposition=lookup_case_disposition.id) left outer join lookup_legal_problem_code on (matter.legal_problem_code=lookup_legal_problem_code.id) left outer join matter_assignment_primary on (matter.id=matter_assignment_primary.matter_id) left outer join users on (matter_assignment_primary.user_id=users.id) left outer join person as userperson on (users.person_id=userperson.id) where ";
  my $just_digits = $phone_number;
  $just_digits =~ s/[^0-9]//g;
  if ($just_digits =~ /^([0-9]{3})([0-9]{4})$/){
    $phone = '%' . $1 . '-' . $2;
  }
  elsif ($just_digits =~ /^([0-9]{3})([0-9]{3})([0-9]{4})$/){
    $phone = $1 . '-' . $2 . '-' . $3;
  }
  print STDERR "Searching phone by $phone\n";
  push (@conditions, "(" . join(" or ", map {qq{person.phone_$_ like ?}} qw/home business mobile fax other/) . ")");
  push (@parameters, $phone, $phone, $phone, $phone, $phone);
  my $search_string = $initial . join(" or ", @conditions) . " order by matter.date_open desc limit 100";
  my $query = $ldref->prepare($search_string) or croak $ldref->errstr;
  $query->execute(@parameters) or croak $query->errstr;
  my @results;
  while (my $row = $query->fetchrow_hashref()){
    push(@caseinfo, $row);
  }
}

my $d = IO::Dir->new($dir) or croak "Could not open $dir";
my (@files);
while (defined(my $subdir = $d->read)){
  next if ($subdir =~ /^\./);
  next unless (-d "$dir/$subdir");
  my $dd = IO::Dir->new("$dir/$subdir") or croak "Could not open $dir/$subdir";
  while (defined(my $file = $dd->read)){
    next unless (-f "$dir/$subdir/$file");
    if ($file =~ /\.txt$/i){
      push(@files, {mimetype => 'text/plain', filename => "$dir/$subdir/$file", nicename => $file})
    }
    if ($file =~ /\.html$/i){
      push(@files, {mimetype => 'text/html', filename => "$dir/$subdir/$file", nicename => $file})
    }
  }
}

my @parts;
my @subparts;
my @links;
foreach my $file (@files){
  #print STDERR "File is " . $file->{filename} . "\n";
  my $body = io( $file->{filename} )->all;
  if ($body){
    while ($body =~ /(https*:\/\/[^\s]+)/gs){
      push(@links, $1);
      #print STDERR "Found a link\n";
    }
  }
  my $tr_body = $body;
  {
    my $index = 1;
    $tr_body =~ s/(https*:\/\/[^\s]+)/'<a href="' . $1 . '">Attachment ' . ($index++) . '<\/a>'/ge;
  }
  $tr_body =~ s/\n\n/<\/p><p>/g;
  $tr_body =~ s/\n/<br>\n/g;
  $tr_body .= "</p>";
  foreach my $d (@caseinfo){
    $body .= $d->{first} . " " . $d->{last} . ", " . $d->{identification_number} . ": " . $d->{disposition} . ", " . $d->{"problem_code"} . "\n";
    $tr_body .= "<p>" . $d->{first} . " " . $d->{last} . ", " . "<a href=\"http://your.cms.hostname.com/matter/dynamic-profile/view/" . $d->{matterid} . "\">" . $d->{identification_number} . "</a>" . ($d->{sfname} ? ' (' . $d->{sfname} . ' ' . $d->{slname} . ')' : '') . ": " . $d->{disposition} . ", " . $d->{"problem_code"} . "</p>\n";
  }
  #print STDERR "Body is $tr_body\n";
  {
    my $mt = Email::MIME->create
      (
       attributes =>
       {
	content_type => "text/html",
	disposition  => "inline",
	charset      => "US-ASCII",
       },
       body => "<html><body><p>" . $tr_body . "</body></html>",
      );
    push(@subparts, $mt);
  }
  {
    my $mt = Email::MIME->create
      (
       attributes =>
       {
	content_type => "text/plain",
	disposition  => "inline",
	charset      => "US-ASCII",
       },
       body => $body,
      );
    push(@subparts, $mt);
  }
}

if (scalar(@links)){
  my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
  $ua->agent('Mozilla/5.0');
  my @imgfiles;
  foreach my $link (@links){
    my $fh = File::Temp->new();
    #print STDERR "Link is $link\n";
    my $response = $ua->get($link, ':content_file' => $fh->filename());
    if ($response->is_success) {
      my $of = File::Temp->new(UNLINK => 0);
      $of->close();
      my $result = system("convert " . $fh->filename() . " pdf:" . $of->filename());
      unless ($result){
	push(@imgfiles, $of);
	#print STDERR "Converted!\n";
	#if (-f $of->filename()){
	  #print STDERR $of->filename() . " exists\n";
	#}
	#else{
	  #print STDERR "File not there\n";
	#}
      }
      #else{
	#print STDERR "Conversion failed!\n";
      #}
    }
    else{
      print STDERR "ERROR: " . $response->status_line . "\n";
    }
  }
  if (scalar(@imgfiles)){
    #print STDERR "There are files!\n";
    my $pdf;
    my $ok = 1;
    if (scalar(@imgfiles) == 1){
      $pdf = $imgfiles[0];
    }
    else{
      $pdf = File::Temp->new();
      $pdf->close();
      #foreach my $imgfile (@imgfiles){
	#my $thefile = $imgfile->filename();
      #if (-f $thefile && ! -z $thefile){
	#print STDERR "Ok\n";
      #}
      #else{
	#print STDERR "Not ok\n";
      #}
    #}
      my $command = "pdftk " . join(" ", map {$_->filename()} @imgfiles) . " cat output " . $pdf->filename();
      #print STDERR "Command is " . $command . "\n";
      my $result = system($command);
      if ($result){
	$ok = 0;
      }
    }
    if ($ok){
      my $nicepdfname = time() . ".pdf";
      my $mt = Email::MIME->create
	(
	 attributes =>
	 {
	  filename     => $nicepdfname,
	  content_type => "application/pdf",
	  encoding     => "base64",
	  name         => $nicepdfname,
	  disposition  => "attachment",
	 },
	 body => io( $pdf->filename() )->all,
	);
      push(@parts, $mt);
    }
  }
}

if (scalar(@subparts)){
  my $mt = Email::MIME->create
    (
     attributes =>
     {
      content_type => "multipart/alternative",
     },
     parts => [ @subparts ],
    );
  unshift(@parts, $mt);
}

my $extra_to = '';
my $numopen = 0;
foreach my $d (@caseinfo){
  $numopen++ if ($d->{disposition} && $d->{disposition} eq "Open");
}
my %extra_recipients;
if ($numopen > 0 && $numopen < 3){
  foreach my $d (@caseinfo){
    if ($d->{sfname} && $d->{slname} && $d->{semail}){
      $extra_recipients{$d->{sfname} . " " . $d->{slname} . " <" . $d->{semail} . ">"} = 1;
    }
    if ($d->{identification_number}){
      $extra_recipients{$d->{identification_number} . " <" . $d->{identification_number} . '@your.cms.hostname.com>'} = 1;
    }
  }
  if (scalar(keys %extra_recipients)){
    $extra_to .= ", " . join(", ", sort keys %extra_recipients);
  }
}

my $email;
if (scalar(@parts) > 1){
  $email = Email::MIME->create
    (
     attributes =>
     {
      content_type => "multipart/mixed",
     },
     header => [
		From    => $from,
		To      => 'Faxes <faxes@philalegal.org>' . $extra_to,
		Bcc     => 'Jonathan Pyle <jpyle@philalegal.org>',
		Subject => $subject,
	       ],
     parts  => [ @parts ],
    );
}
else{
  $email = Email::MIME->create
    (
     attributes =>
     {
      content_type => "multipart/alternative",
     },
     header => [
		From    => $from,
		To      => 'Faxes <faxes@philalegal.org>' . $extra_to,
		Bcc     => 'Jonathan Pyle <jpyle@philalegal.org>',
		Subject => $subject,
	       ],
     parts  => [ @subparts ],
    );
}
#my $testparser = new MIME::Parser;
#$testparser->output_under("/tmp");
#my $testentity = $testparser->parse_data($email->as_string());
#$testentity->dump_skeleton;
#exit;
{
  my $smtp = "192.168.200.35";
  my $sender = Email::Send->new({mailer => 'SMTP'});
  $sender->mailer_args([Host => $smtp]);
  eval { $sender->send($email) };
  if ($@){
    print STDERR "ERROR: $@\n";
    exit;
  }
}

#print STDERR "The nice name is " . $file->{nicename} . "\n";
