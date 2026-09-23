resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: existingVm
  name: 'AzureMonitorLinuxAgent'
  location: 'northcentralus'
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
  tags: {
    project: 'vmrbac-lab'
  }
}


resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-vm1-metrics'
  location: 'northcentralus'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'cpuCounters'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'law-destination'
          workspaceResourceId: '/subscriptions/2576ee8a-f0b4-461e-980c-eb2e7cc9b22e/resourceGroups/rg-vmrbac-project/providers/Microsoft.OperationalInsights/workspaces/law-vmrbac-project'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'law-destination'
        ]
      }
    ]
  }
  tags: {
    project: 'vmrbac-lab'
  }
}

resource existingVm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: 'vm1'
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'dcr-association-vm1'
  scope: existingVm
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

resource cpuAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-vm1-high-cpu'
  location: 'global'
  properties: {
    description: 'Alerts when vm1 CPU exceeds 80% average over 5 minutes'
    severity: 2
    enabled: true
    scopes: [
      existingVm.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: '/subscriptions/2576ee8a-f0b4-461e-980c-eb2e7cc9b22e/resourceGroups/rg-vmrbac-project/providers/microsoft.insights/actionGroups/law'
      }
    ]
  }
  tags: {
    project: 'vmrbac-lab'
  }
}
