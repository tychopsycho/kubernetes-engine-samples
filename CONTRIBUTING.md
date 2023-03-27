# How to become a contributor and submit your own code

## Contributor License Agreements

Before you're able to contribute to this repository, you need to sign a
Contributor License Agreement (CLA). You can follow the links below to
fill out the appropriate CLA (individual, or corporate):

* **[Individual
  CLA](https://developers.google.com/open-source/cla/individual):** You are an individual writing original source code and own the intellectual property.
* **[Corporate
  CLA](https://developers.google.com/open-source/cla/corporate):** You work for a company that allows you to contribute your work.

Follow either of the two links above to access the appropriate CLA and
instructions for how to sign and return it. Once we receive it, we'll be able to
accept your pull requests. You can visit <https://cla.developers.google.com/> to
confirm your current agreements or to sign a new one.

## Contributing a patch

1. [Submit an issue](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/issues/new) describing your proposed changes.
1. The repo owner will respond to your issue promptly. Once accepted:
1. Sign a Contributor License Agreement (see details above) if you haven't done so.
1. Fork the repo, develop and test your code changes.
1. Ensure that your code adheres to the existing style in the sample to which
   you are contributing.
1. Ensure that your code has an appropriate set of unit tests which all pass.
1. Submit a pull request.

## Code reviews

All submissions, including submissions by project members, require review. We
use GitHub pull requests for this purpose. Consult
[GitHub Help](https://help.github.com/articles/about-pull-requests/) for more
information on using pull requests.

## Community guidelines

This project follows
[Google's Open Source Community Guidelines](https://opensource.google/conduct/).

## Samples requirements

All new code sample needs the following requirements:
- A short `README.md` file with an external link pointing to the tutorial using the sample, if 
  applicable. Ideally, there should be only one source of truth for sample instructions.
- A GitHub Action workflow that tests the sample code. At minimum, this should
  dry-run any container image or Terraform configs and pass without any errors.
  [[Example](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/blob/main/.github/workflows/security-ci.yml)]
  - Each container image should build successfully (e.g. `docker build...`)
  - Each Terraform config should validate successfully (e.g. `terraform validate...`)
  - If there are any other simple smoke tests that can be performed, they should also be added here.
- If the sample relies on canonical image artifacts, these can be hosted officially, which requires:
  - Cloud Build configs for all container images that pushes to the `google-samples` artifact registry.
  [[Example](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/blob/main/security/wi-secrets/cloudbuild.yaml)]
  - A Terraform section for the above Cloud Build configs.
  [[Example](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/blob/main/terraform/google-cloud-build-triggers.tf#L194-L207)]
    - Note that in order for the Cloud Build configs to be applied to the
      `google-samples` project, you need to run `terraform init && terraform apply`
      while in that project (admin permissions required).
    - The images will be of the form `us-docker.pkg.dev/google-samples/containers/gke<image_name>:latest`
