<?php

require_once __DIR__ . '/Maintenance.php';

class SendTestEmail extends Maintenance {
    public function __construct() {
        parent::__construct();
        $this->addDescription( 'Send a test email using MediaWiki\'s email functionality.' );
        $this->addOption( 'to', 'Recipient email address', true, true );
        $this->addOption( 'from', 'Sender email address', true, true );
        $this->addOption( 'subject', 'Email subject line', false, true );
        $this->addOption( 'body', 'Email body text', false, true );
        $this->addOption( 'to-name', 'Recipient display name', false, true );
        $this->addOption( 'from-name', 'Sender display name', false, true );
    }

    public function execute() {
        $toEmail = $this->getOption( 'to' );
        $fromEmail = $this->getOption( 'from' );
        $subject = $this->getOption( 'subject', 'Test Email from MediaWiki' );
        $body = $this->getOption( 'body', 'This is a test email to verify SMTP configuration.' );
        $toName = $this->getOption( 'to-name', '' );
        $fromName = $this->getOption( 'from-name', 'MediaWiki' );

        // Add timestamp to body
        $body .= "\n\nSent at: " . date( 'Y-m-d H:i:s T' );

        $to = new MailAddress( $toEmail, $toName );
        $from = new MailAddress( $fromEmail, $fromName );

        $this->output( "Sending test email...\n" );
        $this->output( "From: $fromName <$fromEmail>\n" );
        $this->output( "To: $toName <$toEmail>\n" );
        $this->output( "Subject: $subject\n\n" );

        $result = UserMailer::send( $to, $from, $subject, $body );

        if ( $result->isOK() ) {
            $this->output( "✅ Email sent successfully!\n" );
        } else {
            $this->error( "❌ Failed to send email: " . $result->getWikiText() . "\n" );
        }
    }
}

$maintClass = SendTestEmail::class;
require_once RUN_MAINTENANCE_IF_MAIN;
