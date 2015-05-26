# lstexttwilio

# Twilio configuration

See twilio-screenshot.png for a summary of our Twilio configuration.  When a text message is received, Twilio passes the text message through http://docket.philalegal.org/data/message.php.

## message.php

This is a short bit of PHP that converts a Twilio text message into an e-mail.  It sends an e-mail message to texts@text.jonathanpyle.com.  The MX record associated with text.jonathanpyle.com points to the docket.philalegal.org server.  The mail server on this machine, exim4, processes the e-mail.

  <?php
  /**
  * This section ensures that Twilio gets a response.
  */
  header('Content-type: text/xml');
  echo '<?xml version="1.0" encoding="UTF-8"?>';
  echo '<Response></Response>'; //Place the desired response (if any) here
  /**
  * This section actually sends the email.
  */
  $to = "texts@text.jonathanpyle.com"; // Your email address
  $subject = "Message from {$_REQUEST['From']} at {$_REQUEST['To']}";
  $message = "You have received a message from {$_REQUEST['From']}.\n\n
  {$_REQUEST['Body']}";
  if ($_REQUEST['NumMedia'] > 0){
	$message .= "\n\nLinks to attached files:\n";
  }
  for ($x = 0; $x < $_REQUEST['NumMedia']; $x++) {
	$message .= "\n".$_REQUEST['MediaUrl'.$x]; 
  } 
  $headers = "From: jpyle@philalegal.org"; // Who should it come from?
  mail($to, $subject, $message, $headers);

## callreply.pl

Twilio calls this script when someone calls our texting number.  This script instructs Twilio to play the audio file located at http://docket.philalegal.org/auto-reply.mp3 for the caller.  This mp3 file simply tells the caller that they need to call a different number.

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

## auto-reply.mp3

This mp3 file is referenced in callreply.pl, above.

# E-mail server configuration for processing incoming text messages

When the e-mail server at docket.philalegal.org receives an e-mail to the recipient "texts," it pipes the e-mail through the script located at /usr/lib/cgi-bin/read-text.pl.

The exim4 configuration file, /etc/exim4/exim4.conf.template, contains the following lines:

  ### router/100_exim4-config_domain_literal
  #################################

  central_filter:
	driver = redirect
	domains = +local_domains
	file = /etc/exim4/textmessagefilter.txt
	user = jpyle
	group = jpyle
	no_verify
	allow_filter
	allow_freeze
	pipe_transport = address_pipe

## textmessagefilter.txt

The file /etc/exim4/textmessagefilter.txt, which is referenced in the exim4 configuration above, is a short file with the following contents:

  #Exim filter
  if $local_part is "texts"
  then
  pipe /usr/lib/cgi-bin/read-text.pl
  seen finish
  endif

# Processing the e-mail containing the incoming text message

## read-text.pl

This Perl script reads the e-mail containing the SMS/MMS message.  It MMS images into a single attached PDF file.  It uses an SMTP server located at 192.168.200.35 to send an e-mail to faxes@philalegal.org (a group mailbox) as well as the e-mail address of the case, as well as the e-mail address of the primary advocate in the case.

# Sending text messages from the CMS

## instruction-on-profile-page.html

Add this HTML as an instruction to the bottom of the Main Profile.  Make sure to check "Format as HTML."

## instruction-next-to-address.html

Add this HTML as an instruction in the tab block next to the address, where you want the user interface to appear.  Make sure to check "Format as HTML."

## send-text.pl

This script is run from an Ajax call from the Javascript code located in the HTML in instruction-next-to-address.html.  If this is going to run on a different server than the CMS web server, to get around the cross-site scripting restriction, you will need to configure the web server to allow the script to be called as though it is a local script.

The script sends the text message to Twilio and also sends it as an e-mail to the CMS.


