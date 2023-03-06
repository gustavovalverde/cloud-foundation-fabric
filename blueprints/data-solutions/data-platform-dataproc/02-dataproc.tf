# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# tfdoc:file:description Cloud Dataproc resources.

locals {
  iam_prc = {
    "roles/bigquery.jobUser" = [
      module.processing-sa-dp-0.iam_email, local.groups_iam.data-engineers
    ]
  }
  processing_dp_subnet = (
    local.use_shared_vpc
    ? var.network_config.subnet_self_links.orchestration
    : values(module.processing-vpc.0.subnet_self_links)[0]
  )
  processing_dp_vpc = (
    local.use_shared_vpc
    ? var.network_config.network_self_link
    : module.processing-vpc.0.self_link
  )
}

module "processing-cs-dp-history" {
  source         = "../../../modules/gcs"
  project_id     = module.processing-project.project_id
  prefix         = var.prefix
  name           = "prc-cs-dp-history"
  location       = var.region
  storage_class  = "REGIONAL"
  encryption_key = try(local.service_encryption_keys.storage, null)
}

module "processing-sa-dp-0" {
  source       = "../../../modules/iam-service-account"
  project_id   = module.processing-project.project_id
  prefix       = var.prefix
  name         = "prc-dp-0"
  display_name = "Dataproc service account"
  iam = {
    "roles/iam.serviceAccountTokenCreator" = [
      local.groups_iam.data-engineers,
      module.processing-sa-cmp-0.iam_email
    ],
    "roles/iam.serviceAccountUser" = [
      module.processing-sa-cmp-0.iam_email
    ]
  }
}

module "processing-dp-staging-0" {
  source         = "../../../modules/gcs"
  project_id     = module.processing-project.project_id
  prefix         = var.prefix
  name           = "prc-stg-0"
  location       = var.location
  storage_class  = "MULTI_REGIONAL"
  encryption_key = try(local.service_encryption_keys.storage, null)
}

module "processing-dp-temp-0" {
  source         = "../../../modules/gcs"
  project_id     = module.processing-project.project_id
  prefix         = var.prefix
  name           = "prc-tmp-0"
  location       = var.location
  storage_class  = "MULTI_REGIONAL"
  encryption_key = try(local.service_encryption_keys.storage, null)
}

module "processing-dp-log-0" {
  source         = "../../../modules/gcs"
  project_id     = module.processing-project.project_id
  prefix         = var.prefix
  name           = "prc-log-0"
  location       = var.location
  storage_class  = "MULTI_REGIONAL"
  encryption_key = try(local.service_encryption_keys.storage, null)
}

module "processing-dp-historyserver" {
  source     = "../../../modules/dataproc"
  project_id = module.processing-project.project_id
  name       = "hystory-server"
  prefix     = var.prefix
  region     = var.region
  dataproc_config = {
    cluster_config = {
      staging_bucket = module.processing-dp-staging-0.name
      temp_bucket    = module.processing-dp-temp-0.name
      gce_cluster_config = {
        subnetwork             = module.processing-vpc[0].subnets["${var.region}/${var.prefix}-processing"].self_link
        zone                   = "${var.region}-b"
        service_account        = module.processing-sa-dp-0.email
        service_account_scopes = ["cloud-platform"]
        internal_ip_only       = true
      }
      worker_config = {
        num_instances    = 0
        machine_type     = null
        min_cpu_platform = null
        image_uri        = null
      }
      software_config = {
        override_properties = {
          "dataproc:dataproc.allow.zero.workers"                                   = "true"
          "dataproc:job.history.to-gcs.enabled"                                    = "true"
          "spark:spark.history.fs.logDirectory"                                    = "gs://${module.processing-dp-staging-0.name}/*/spark-job-history"
          "spark:spark.eventLog.dir"                                               = "gs://${module.processing-dp-staging-0.name}/*/spark-job-history"
          "spark:spark.history.custom.executor.log.url.applyIncompleteApplication" = "false"
          "spark:spark.history.custom.executor.log.url"                            = "{{YARN_LOG_SERVER_URL}}/{{NM_HOST}}:{{NM_PORT}}/{{CONTAINER_ID}}/{{CONTAINER_ID}}/{{USER}}/{{FILE_NAME}}"
        }
      }
      endpoint_config = {
        enable_http_port_access = "true"
      }
      encryption_config = {
        kms_key_name = try(local.service_encryption_keys.compute, null)
      }
    }
  }
}
