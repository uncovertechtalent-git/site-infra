mock_provider "cloudflare" {
  mock_resource "cloudflare_zero_trust_access_identity_provider" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000000a"
    }
  }

  mock_resource "cloudflare_zero_trust_access_policy" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000000b"
    }
  }
}

variables {
  account_id     = "0123456789abcdef0123456789abcdef"
  name           = "example tools"
  hostnames      = ["a.example.org", "b.example.org", "c.example.org"]
  allowed_emails = ["person@example.org"]
}

run "only_the_listed_emails_get_in" {
  command = apply

  assert {
    condition     = cloudflare_zero_trust_access_policy.allow.decision == "allow"
    error_message = "The one policy is an Allow policy."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.allow.include) == 1 && one(cloudflare_zero_trust_access_policy.allow.include).email.email == "person@example.org"
    error_message = "The include rules are exactly the listed emails."
  }

  assert {
    condition     = cloudflare_zero_trust_access_policy.allow.exclude == null || length(coalesce(cloudflare_zero_trust_access_policy.allow.exclude, [])) == 0
    error_message = "No exclude rule widens or narrows the list silently."
  }
}

run "every_hostname_is_covered" {
  command = apply

  assert {
    condition     = [for d in cloudflare_zero_trust_access_application.this.destinations : d.uri] == ["a.example.org", "b.example.org", "c.example.org"]
    error_message = "The application covers every listed hostname."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this.type == "self_hosted"
    error_message = "A self-hosted application in front of the tunnel."
  }

  assert {
    condition     = one(cloudflare_zero_trust_access_application.this.policies).id == "00000000-0000-0000-0000-00000000000b"
    error_message = "The application uses the Allow policy and nothing else."
  }
}

run "one_time_pin_is_the_login" {
  command = apply

  assert {
    condition     = cloudflare_zero_trust_access_identity_provider.otp[0].type == "onetimepin"
    error_message = "The one-time PIN login method is created."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this.allowed_idps == toset(["00000000-0000-0000-0000-00000000000a"])
    error_message = "The application allows the one-time PIN only."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this.auto_redirect_to_identity
    error_message = "With one login method, Access goes straight to it."
  }
}

run "an_empty_allow_list_is_refused" {
  command = plan

  variables {
    allowed_emails = []
  }

  expect_failures = [var.allowed_emails]
}

run "a_wildcard_is_refused" {
  command = plan

  variables {
    allowed_emails = ["*"]
  }

  expect_failures = [var.allowed_emails]
}

run "hostnames_without_scheme" {
  command = plan

  variables {
    hostnames = ["https://a.example.org/"]
  }

  expect_failures = [var.hostnames]
}
