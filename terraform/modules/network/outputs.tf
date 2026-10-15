output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  value = aws_subnet.isolated[*].id
}

output "security_group_ids" {
  value = {
    alb    = aws_security_group.alb.id
    app    = aws_security_group.app.id
    worker = aws_security_group.worker.id
    db     = aws_security_group.db.id
  }
}
