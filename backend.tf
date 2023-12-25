terraform {
  cloud {
    organization = "2up"
    workspaces {
      name = "atlassian"
    }
  }
}