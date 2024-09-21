#!/bin/bash

sendMail() {

    local recipient_email=$1
    # Set the subject and body of the email
    subject="Daily Reminder"
    body="Hello! This is your daily reminder message."

    # Alternatively, you can use 'sendmail':
    echo -e "Subject:$subject\n$body" | ssmtp "$recipient_email"

}

sendMail "sunnepazzy123@gmail.com"
