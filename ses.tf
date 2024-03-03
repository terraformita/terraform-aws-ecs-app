resource "aws_ses_email_identity" "sender_email" {
  count = var.mail_sending.enabled ? 1 : 0
  email = var.mail_sending.from_address
}
