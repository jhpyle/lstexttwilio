#!/usr/bin/perl

use strict;
use Carp;
use CGI qw/:standard/;;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use DBI;
use WWW::Twilio::API;

my $mytextnumber = '2159872680';

my $q = new CGI;

my $ldref = DBI->connect('dbi:Pg:dbname=pla_live;host=192.168.200.204', 'psti', 'secretsecret', {AutoCommit => 1}) or croak DBI->errstr;

my $twilio = WWW::Twilio::API->new(AccountSid => 'ACfad8e6secretsecret823523b9358',
				   AuthToken  => '86549c9asecretsecret9546');

my $id = $q->param('id');
my $phone_number = $q->param('number');
my $text_message = $q->param('message');
my $snum = $q->param('snum');
my ($sfname, $slname, $office, $office_phone);
my $squery = $ldref->prepare("select users.person_id, person.first, person.last, office.name as office_name, person.phone_business from users left outer join person on (users.person_id=person.id) left outer join office on (users.office_id=office.id) where person.first || ' ' || person.last ilike ?") or croak $ldref->errstr;
$squery->execute($snum) or croak $squery->errstr;
while (my $d = $squery->fetchrow_hashref()){
  $sfname = $d->{first};
  $slname = $d->{last};
  $office = $d->{office_name};
  $office_phone = $d->{phone_business};
}
if ($sfname && $slname && $office_phone){
  $text_message .= "\n -- $sfname $slname, PLA ($office_phone)";
}

my $case_id;
if ($id){
  my $query = $ldref->prepare("select identification_number from matter where id=?") or croak $ldref->stderr;
  $query->execute($id) or croak $query->errstr;
  while (my $d = $query->fetchrow_hashref()){
    $case_id = $d->{"identification_number"};
  }
}

print $q->header(-type => 'text/plain', -expires => 'now');

if ($case_id && $phone_number && $text_message){
  $phone_number =~ s/[^0-9]//g;
  my $nice_phone_number = $phone_number;
  $nice_phone_number =~ s/([0-9]{3})([0-9]{3})([0-9]{4})/\1-\2-\3/;
  my $response = $twilio->POST('SMS/Messages',
			       From => $mytextnumber,
			       To   => $phone_number,
			       Body => $text_message);

  my $message = Email::MIME->create
    (
     header_str => [
		    From    => 'textmessage@philalegal.org',
		    To      => $case_id . '@your.cms.hostname.com',
		    Subject => 'Text message sent',
		   ],
     attributes => {
		    encoding => 'quoted-printable',
		    charset  => 'ISO-8859-1',
		   },
     body_str => "To: $nice_phone_number\n" . $text_message . "\n",
    );
  sendmail($message);
  print "Text message sent and copy e-mailed to case file.\n";
  #print "<pre>" . $response->{content} . "</pre>\n";
}
else{
  print "Text message not sent.  There was an error.\n";
}

