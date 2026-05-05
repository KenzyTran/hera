# Hera KB prod environment values.
# All three of these have defaults in variables.tf; this file makes them explicit for the workshop reader.
# Override at apply time with: terraform apply -var=region=us-east-1

region      = "ap-northeast-1"
env         = "prod"
name_prefix = "hera"
