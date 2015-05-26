#! /usr/bin/perl -w

use strict;
use warnings;
use Carp;
use WWW::Twilio::API;
use DBI;
use Date::Manip;

my $on = 1;

#my $mynumber = '4845762135';
#my $mynumber = '2153919686';
my $mytextnumber = '2159872680';
my $mynumber = '6106231875';
my $date = DateCalc('today', '+ 1 business day');
my $tomorrow = ParseDate('tomorrow');

my $dref = DBI->connect('dbi:Pg:dbname=cls', '', '', {AutoCommit => 1}) or croak DBI->errstr;

my $query = $dref->prepare("select id, number, status, apptdatetime, callback, apptdatetime::date as apptdate from twiliotodo where status=? and apptdatetime::date=?") or croak $dref->errstr;

$query->execute('Not called', UnixDate($date, '%m/%d/%Y')) or croak $query->errstr;

my $update = $dref->prepare("update twiliotodo set voicemessage=?, textmessage=?, status=? where id=?") or croak $dref->errstr;

my $updatestatus = $dref->prepare("update twiliotodo set status=? where id=?") or croak $dref->errstr;

my $twilio = WWW::Twilio::API->new(AccountSid => 'ACfad8e668b5f9e15d499ab823523b9358',
				   AuthToken  => '86549c9a407b25d32f21c758e7b09546');

while (my $d = $query->fetchrow_hashref()){
  my $day = ($d->{apptdate} eq $tomorrow) ? UnixDate($d->{apptdate}, 'tomorrow, %B %e') : UnixDate($date, 'on %A, %B %e');
  if ($day =~ /1$/){
    $day .= "st";
  }
  elsif ($day =~ /2$/){
    $day .= "nd";
  }
  elsif ($day =~ /3$/){
    $day .= "rd";
  }
  else{
    $day .= "th";
  }
  $day =~ s/  +/ /g;

  my $time = UnixDate($d->{apptdatetime}, '%i:%M %p');
  $time =~ s/AM/a.m./;
  $time =~ s/PM/p.m./;
  $time =~ s/^0//;
  $time =~ s/  +/ /g;

  my $themessage = "This is a reminder that you have an appointment at Philadelphia Legal Assistance $day, at $time . If you need to cancel the appointment, or you have any questions, please call " . ($d->{callback} // '215-981-3800') . ".  Thank you. . ";

  my $thetext = "Reminder: you have an appointment at PLA $day, at $time  Call " . ($d->{callback} // '215-981-3800') . " with questions.";

  #print "Message: $themessage\nText: $thetext\n";
  $update->execute($themessage, $thetext, 'Ready to call', $d->{id}) or croak $update->errstr;
}

my $doquery = $dref->prepare("select id, number, textmessage from twiliotodo where status=?") or croak $dref->errstr;

$doquery->execute('Ready to call') or croak $query->errstr;

my @todo;
while (my $d = $doquery->fetchrow_hashref()){
  push(@todo, $d);
}

foreach my $d (@todo){
  my $number = $d->{number};
  $number =~ s/[^0-9]//g;
  if($on){
    print "Send text message to $number with content $d->{textmessage}\n";
    my $response = $twilio->POST('SMS/Messages',
				 From => $mytextnumber,
				 To   => $number,
				 Body => $d->{textmessage});
    print $response->{content};
  }
  if(0 && $on){
    print "Send voice message to $d->{number} with content http://docket.philalegal.org/makecall/$d->{id}\n";
    my $response = $twilio->POST('Calls',
				 From      => $mynumber,
				 To        => $number,
				 FriendlyName => 'Philadelphia Legal Assistance',
				 Url       => "http://docket.philalegal.org/makecall/$d->{id}");
    print $response->{content};
  }
  $updatestatus->execute('Done', $d->{id}) or croak $updatestatus->errstr;
}
