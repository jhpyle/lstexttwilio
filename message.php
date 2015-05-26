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
