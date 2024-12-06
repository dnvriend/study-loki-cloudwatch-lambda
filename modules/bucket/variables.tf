variable "bucket_name" {
  description = "The name of the S3 bucket to create"
  type        = string
}

variable "intelligent_tiering_days" {
  description = "The number of days Intelligent-Tiering will wait before moving an object to the infrequent access tier"
  type        = number
  default     = 90
}

# when destroying this resource, this will delete all objects in the bucket
variable "force_destroy" {
  description = "A boolean that indicates all objects should be deleted from the bucket so that the bucket can be destroyed without error"
  type        = bool
  default     = false
}
