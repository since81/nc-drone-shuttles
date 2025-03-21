resource "kubernetes_namespace_v1" "blog" {
  metadata {
    name = "blog"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "blog_claim" {
  metadata {
    name      = "blog-claim"
    namespace = "blog"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "azurefile-csi"

    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "blog" {
  metadata {
    name      = "blog"
    namespace = "blog"
    labels = {
      app = "blog"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app = "blog"
      }
    }

    template {
      metadata {
        labels = {
          app = "blog"
        }
      }

      spec {
        volume {
          name = "blog-content"

          persistent_volume_claim {
            claim_name = "blog-claim"
          }
        }
        volume {
          name = "database-secrets"
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "azure-database-kv"
            }
          }
        }
        volume {
          name = "smtp-secrets"
          csi {
            driver    = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = "azure-smtp-kv"
            }
          }
        }

        container {
          name              = "ghost"
          image             = "ghost:5"
          image_pull_policy = "Always"

          env {
            name  = "url"
            value = "http://drones-shuttles.org"
          }
          env {
            name  = "mail__from"
            value = "no-reply@mg.drones-shuttles.org"
          }
          env {
            name  = "mail__transport"
            value = "SMTP"
          }
          env {
            name  = "mail__options__service"
            value = "Mailgun"
          }
          env {
            name = "mail__options__auth__user"
            value_from {
              secret_key_ref {
                name = "smtp-connection"
                key  = "mail__options__auth__user"
              }
            }
          }
          env {
            name = "mail__options__auth__pass"
            value_from {
              secret_key_ref {
                name = "smtp-connection"
                key  = "mail__options__auth__pass"
              }
            }
          }
          env {
            name  = "database__client"
            value = "mysql"
          }
          env {
            name = "database__connection__host"
            value_from {
              secret_key_ref {
                name = "database-connection"
                key  = "database__connection__host"
              }
            }
          }
          env {
            name = "database__connection__user"
            value_from {
              secret_key_ref {
                name = "database-connection"
                key  = "database__connection__user"
              }
            }
          }
          env {
            name = "database__connection__password"
            value_from {
              secret_key_ref {
                name = "database-connection"
                key  = "database__connection__password"
              }
            }
          }
          env {
            name = "database__connection__database"
            value_from {
              secret_key_ref {
                name = "database-connection"
                key  = "database__connection__database"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 2368
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          volume_mount {
            name       = "blog-content"
            mount_path = "/var/lib/ghost/content"
          }
          volume_mount {
            name       = "database-secrets"
            mount_path = "/mnt/database-secrets-store"
            read_only  = true
          }
          volume_mount {
            name       = "smtp-secrets"
            mount_path = "/mnt/smtp-secrets-store"
            read_only  = true
          }

          resources {
            limits = {
              cpu    = "1"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          port {
            name           = "http"
            container_port = 2368
            protocol       = "TCP"
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [
    kubernetes_persistent_volume_claim_v1.blog_claim,
    kubernetes_manifest.secrets_store_database,
    kubernetes_manifest.secrets_store_smtp
  ]
}

resource "kubernetes_service_v1" "blog" {
  metadata {
    name      = "blog"
    namespace = "blog"
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "blog"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 2368
    }
  }

  depends_on = [
    kubernetes_deployment_v1.blog
  ]
}

resource "kubernetes_ingress_v1" "ingress_blog_any_host" {
  metadata {
    name      = "ingress-blog-any-host"
    namespace = "blog"
    annotations = {
      "kubernetes.io/ingress.class"                   = "azure/application-gateway"
      "appgw.ingress.kubernetes.io/backend-protocol"  = "http"
      "appgw.ingress.kubernetes.io/request-body-size" = "16m"
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/"
          backend {
            service {
              name = "blog"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_v1.blog
  ]
}
