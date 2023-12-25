variable "vpc_cidr_block" {
	type = string
	description = "To set cidr for vpc"
}
variable "subnet_cidr_block" {
	type = string
	description = "To set cidr for subnet"
}
variable "availability_zone" {
	# type = string
	type = list(string)
	description = "To set AWS availability region"
	default = ["ap-northeast-2a", "ap-northeast-2b"]
}
variable "env_prefix" {
	type = string
	description = "Set as dev or prod or qa etc. based on desired environment"
}
variable "instance_type" {
	type = string
	description = "To desired instance type for AWS EC2 instance"
}
