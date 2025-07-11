import { Construct } from 'constructs';
import { TerraformStack, TerraformOutput, S3Backend } from 'cdktf';
import { DigitaloceanProvider } from '@cdktf/provider-digitalocean/lib/provider';
import { KubernetesCluster } from '@cdktf/provider-digitalocean/lib/kubernetes-cluster';
import { Loadbalancer } from '@cdktf/provider-digitalocean/lib/loadbalancer';
import { DataDigitaloceanDomain } from '@cdktf/provider-digitalocean/lib/data-digitalocean-domain';
import { DataDigitaloceanKubernetesVersions } from '@cdktf/provider-digitalocean/lib/data-digitalocean-kubernetes-versions';
import { Record } from '@cdktf/provider-digitalocean/lib/record';
import { Certificate } from '@cdktf/provider-digitalocean/lib/certificate';
import { Config, Environment } from '../config/schema';

export interface DigitalOceanClusterStackProps {
  projectName: string;
  environment: Environment;
  config: Config;
}

export class DigitalOceanClusterStack extends TerraformStack {
  public readonly cluster: KubernetesCluster;
  public readonly loadBalancer: Loadbalancer;
  public readonly domain: DataDigitaloceanDomain;
  public readonly certificate: Certificate;

  constructor(scope: Construct, id: string, props: DigitalOceanClusterStackProps) {
    super(scope, id);

    const { projectName, environment } = props;
    const clusterName = `${projectName}-${environment.name}`;

    // Configure S3 backend for Terraform state
    new S3Backend(this, {
      bucket: process.env.TERRAFORM_STATE_BUCKET!,
      key: `${projectName}/${environment.name}-cluster.tfstate`,
      region: process.env.TERRAFORM_STATE_REGION!,
      encrypt: true,
    });

    // DigitalOcean provider
    new DigitaloceanProvider(this, 'digitalocean', {
      token: process.env.DIGITALOCEAN_TOKEN!,
    });

    // Get available Kubernetes versions
    const k8sVersions = new DataDigitaloceanKubernetesVersions(this, 'k8s-versions', {});

    // Kubernetes cluster
    this.cluster = new KubernetesCluster(this, 'cluster', {
      name: clusterName,
      region: environment.cluster.region,
      version: environment.cluster.version || k8sVersions.latestVersion,
      nodePool: {
        name: `${clusterName}-default-pool`,
        size: environment.cluster.nodeSize,
        nodeCount: environment.cluster.nodeCount,
        autoScale:
          environment.cluster.minNodes !== undefined || environment.cluster.maxNodes !== undefined,
        minNodes: environment.cluster.minNodes || Math.max(1, environment.cluster.nodeCount - 1),
        maxNodes: environment.cluster.maxNodes || environment.cluster.nodeCount + 2,
      },
      tags: [projectName, environment.name, 'managed-by-cdktf'],
      maintenancePolicy: {
        startTime: '04:00',
        day: 'sunday',
      },
      ha: environment.cluster.haControlPlane ?? false,
    });

    // Domain management (reference existing domain created by setup.ts)
    this.domain = new DataDigitaloceanDomain(this, 'domain', {
      name: environment.domain,
    });

    // Create Let's Encrypt certificate for the domain
    this.certificate = new Certificate(this, 'lb-certificate', {
      name: `${clusterName}-lb-cert`,
      type: 'lets_encrypt',
      domains: [environment.domain, `*.${environment.domain}`],
    });

    // Load balancer for ingress
    this.loadBalancer = new Loadbalancer(this, 'ingress-lb', {
      name: `${clusterName}-ingress`,
      type: 'regional',
      region: environment.cluster.region,
      size: 'lb-small',
      lifecycle: {
        ignoreChanges: ['type'],
      },
      forwardingRule: [
        {
          entryProtocol: 'http',
          entryPort: 80,
          targetProtocol: 'http',
          targetPort: 80,
        },
        {
          entryProtocol: 'https',
          entryPort: 443,
          targetProtocol: 'https',
          targetPort: 443,
          certificateName: this.certificate.name,
        },
      ],
      healthcheck: {
        protocol: 'http',
        port: 80,
        path: '/healthz',
        checkIntervalSeconds: 10,
        responseTimeoutSeconds: 5,
        unhealthyThreshold: 3,
        healthyThreshold: 2,
      },
      dropletTag: `${clusterName}-worker`,
    });

    // Create root A record pointing to load balancer
    new Record(this, 'root-record', {
      domain: this.domain.name,
      type: 'A',
      name: '@',
      value: this.loadBalancer.ip,
      ttl: 300,
    });

    // Application DNS records are managed by external-dns based on ingress annotations

    // Wildcard record for additional services
    new Record(this, 'wildcard-record', {
      domain: this.domain.name,
      type: 'A',
      name: '*',
      value: this.loadBalancer.ip,
      ttl: 300,
    });

    // Outputs
    new TerraformOutput(this, 'cluster_id', {
      value: this.cluster.id,
      description: 'The ID of the Kubernetes cluster',
    });

    new TerraformOutput(this, 'cluster_name', {
      value: this.cluster.name,
      description: 'The name of the Kubernetes cluster',
    });

    new TerraformOutput(this, 'cluster_endpoint', {
      value: this.cluster.endpoint,
      description: 'The endpoint of the Kubernetes cluster',
    });

    new TerraformOutput(this, 'cluster_status', {
      value: this.cluster.status,
      description: 'The status of the Kubernetes cluster',
    });

    new TerraformOutput(this, 'cluster_region', {
      value: this.cluster.region,
      description: 'The region of the Kubernetes cluster',
    });

    new TerraformOutput(this, 'kubeconfig', {
      value: this.cluster.kubeConfig,
      sensitive: true,
      description: 'The kubeconfig for the cluster',
    });

    new TerraformOutput(this, 'load_balancer_ip', {
      value: this.loadBalancer.ip,
      description: 'The IP address of the load balancer',
    });

    new TerraformOutput(this, 'domain_name', {
      value: this.domain.name,
      description: 'The configured domain name',
    });

    new TerraformOutput(this, 'application_urls', {
      value: ['auth', 'chat', 'files', 'mail'].map(sub => `https://${sub}.${environment.domain}`),
      description: 'URLs for deployed applications (DNS managed by external-dns)',
    });
  }
}
