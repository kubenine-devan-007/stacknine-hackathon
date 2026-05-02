resource "aws_service_discovery_private_dns_namespace" "internal" {
  name        = "stacknine.local"
  description = "Private DNS for extractor/parser (task §4 hint)"
  vpc         = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "extractor" {
  name = "extractor"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "parser" {
  name = "parser"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
