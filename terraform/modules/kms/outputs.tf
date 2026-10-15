output "data_key_arn" {
  value = aws_kms_key.data.arn
}

output "bvn_encrypt_key_arn" {
  value = aws_kms_key.bvn_encrypt.arn
}

output "bvn_mac_key_arn" {
  value = aws_kms_key.bvn_mac.arn
}
