//
//  DeploymentView.swift
//  Zeitgeist
//
//  Created by Daniel Eden on 01/08/2020.
//  Copyright © 2020 Daniel Eden. All rights reserved.
//

import SwiftUI

struct LatestDeploymentWidgetView: View {
  var config: LatestDeploymentEntry
  
  var body: some View {
    VStack(alignment: .leading) {
      if config.isMockDeployment != true {
        DeploymentStateIndicator(state: config.deployment.state, verbose: true)
          .font(Font.caption.bold())
          .padding(.bottom, 2)
        
        Text(config.deployment.commit?.commitMessage ?? "Manual Deployment")
          .font(.subheadline)
          .fontWeight(.bold)
          .lineLimit(3)
          .foregroundColor(.primary)
        
        Text(config.deployment.date, style: .relative)
          .font(.caption)
        Text(config.deployment.project)
          .lineLimit(1)
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        Text("No Deployments Found")
          .font(.caption)
          .fontWeight(.bold)
          .foregroundColor(.secondary)
          .frame(minWidth: 0, maxWidth: .infinity)
      }
      
      Spacer()
      
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Image(systemName: "person.2.fill")
        Text(config.team.name)
      }.font(.caption2).foregroundColor(.secondary).imageScale(.small).lineLimit(1)
    }
    .padding()
    .background(Color.systemBackground)
    .background(LinearGradient(
      gradient: Gradient(
        colors: [.systemBackground, .secondarySystemBackground]
      ),
      startPoint: .top,
      endPoint: .bottom
    ))
    .widgetURL(URL(string: "zeitgeist://deployment/\(config.team.id)/\(config.deployment.id)")!)
  }
}
