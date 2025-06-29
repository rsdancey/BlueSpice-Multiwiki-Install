<?php

require_once __DIR__ . '/Maintenance.php';

class SendTestEmail extends Maintenance {
    public function __construct() {
        parent::__construct();
        $this->addDescription( 'Send a test email using MediaWiki\'s email functionality.' );
        $this->addOption( 'to', 'Recipient email address', true, true );
        $this->addOption( 'from', 'Sender email address (defaults to $wgPasswordSender if not specified)', false, true );
        $this->addOption( 'subject', 'Email subject line', false, true );
        $this->addOption( 'body', 'Email body text', false, true );
        $this->addOption( 'to-name', 'Recipient display name', false, true );
        $this->addOption( 'from-name', 'Sender display name', false, true );
    }

    public function execute() {
        global $wgPasswordSender, $wgSitename;
        
        $toEmail = $this->getOption( 'to' );
        
        // Use $wgPasswordSender as default if no --from is specified
        $fromEmail = $this->getOption( 'from' );
        if ( !$fromEmail ) {
            $fromEmail = $wgPasswordSender;
            if ( !$fromEmail ) {
                $this->fatalError( "No sender email specified and \$wgPasswordSender is not configured. Use --from to specify a sender." );
            }
            $this->output( "Using configured sender from \$wgPasswordSender: $fromEmail\n" );
        }
        
        $subject = $this->getOption( 'subject', 'Test Email from MediaWiki' );
        $body = $this->getOption( 'body', 'This is a test email to verify SMTP configuration.' );
        $toName = $this->getOption( 'to-name', '' );
        
        // Use $wgSitename as default sender name if no --from-name is specified
        $fromName = $this->getOption( 'from-name' );
        if ( !$fromName ) {
            $fromName = $wgSitename ?: 'MediaWiki';
        }

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
