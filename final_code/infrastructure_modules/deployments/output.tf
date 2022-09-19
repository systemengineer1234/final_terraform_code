output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ebs_csi_iam_policy" {
  value = data.http.ebs_csi_iam_policy.body
}