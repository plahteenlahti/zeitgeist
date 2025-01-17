//
//  DeploymentsListView.swift
//  Zeitgeist
//
//  Created by Daniel Eden on 13/03/2020.
//  Copyright © 2020 Daniel Eden. All rights reserved.
//

import Foundation
import SwiftUI

enum SizeClassHack {
  case regular
}

#if os(macOS)
typealias ZGDeploymentsListStyle = SidebarListStyle
let filterToolbarButtonPosition: ToolbarItemPlacement = .automatic
let filterStatusAlignment: HorizontalAlignment = .trailing
#else
typealias ZGDeploymentsListStyle = PlainListStyle
let filterToolbarButtonPosition: ToolbarItemPlacement = .bottomBar
let filterStatusAlignment: HorizontalAlignment = .center
#endif

struct DeploymentsListView: View {
  @EnvironmentObject var vercelFetcher: VercelFetcher
  @Environment(\.deeplink) var deeplink
  
  #if os(macOS)
  var horizontalSizeClass: SizeClassHack = .regular
  #else
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  #endif
  @State var teamID: String?
  @State var selectedDeploymentID: String?
  
  @State var projectFilter: ProjectNameFilter = .allProjects
  @State var stateFilter: StateFilter = .allStates
  @State var productionFilter = false
  @State var filterVisible = false
  
  var body: some View {
    let team = vercelFetcher.teams.first(where: { $0.id == teamID }) ?? VercelTeam()
    let deployments = vercelFetcher.deploymentsStore.store[team.id] ?? []
    let projects = vercelFetcher.projectsStore.store[team.id] ?? []
    
    return Group {
      if filteredDeployments(deployments).isEmpty {
        if vercelFetcher.fetchState == .loading {
          ProgressView("Loading deployments...")
        } else {
          VStack(spacing: 0) {
            Spacer()
            Text("emptyState")
              .foregroundColor(.secondary)
            Spacer()
          }
        }
      } else {
        List(filteredDeployments(deployments), id: \.self.id) { deployment in
          NavigationLink(
            destination: DeploymentDetailView(teamID: teamID ?? "-1", deploymentID: deployment.id),
            tag: deployment.id,
            selection: $selectedDeploymentID
          ) {
            DeploymentsListRowView(deployment: deployment)
          }
        }
        .listStyle(ZGDeploymentsListStyle())
      }
    }
    .onAppear {
      if self.selectedDeploymentID == nil && horizontalSizeClass == .regular {
        self.selectedDeploymentID = filteredDeployments(deployments).first?.id
      }
    }
    .onChange(of: deeplink) { deeplink in
      DispatchQueue.main.async {
        if case .deployment(let teamId, let deploymentId) = deeplink {
          self.selectedDeploymentID = deploymentId
          self.teamID = teamId
        }
      }
    }
    .navigationTitle(Text("Deployments"))
    .toolbar {
      ToolbarItem(placement: .status) {
        VStack(alignment: filterStatusAlignment) {
          Text(team.name).fontWeight(.semibold)
          
          if filtersApplied() {
            Text("\(filteredDeployments(deployments).count) of \(deployments.count) deployments shown")
            if !IS_MACOS {
              Button(action: { self.filterVisible.toggle() }, label: {
                Text("Filters applied")
                  .font(.caption)
                  .foregroundColor(.accentColor)
              })
            }
          } else {
            Text("\(deployments.count) deployments shown")
          }
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }
      
      ToolbarItem(placement: filterToolbarButtonPosition) {
        Button(action: { self.filterVisible.toggle() }, label: {
          Label(
            "Filter by project",
            systemImage: filtersApplied()
              ? "line.horizontal.3.decrease.circle.fill"
              : "line.horizontal.3.decrease.circle"
          ).labelStyle(IconOnlyLabelStyle())
        })
      }
    }
    .sheet(isPresented: self.$filterVisible) {
      DeploymentsFilterView(
        projects: projects,
        projectFilter: self.$projectFilter,
        stateFilter: self.$stateFilter,
        productionFilter: self.$productionFilter
      )
    }
  }
  
  func filteredDeployments(_ deployments: [Deployment]) -> [Deployment] {
    return deployments.filter { deployment -> Bool in
      switch self.projectFilter {
      case .allProjects:
        return true
      case .filteredByProjectName(let name):
        return name == deployment.project
      }
    }
    .filter { deployment -> Bool in
      switch self.stateFilter {
      case .allStates:
        return true
      case .filteredByState(let state):
        return state == deployment.state
      }
    }
    .filter { deployment -> Bool in
      return productionFilter ? deployment.target == .production : true
    }
  }
  
  func filtersApplied() -> Bool {
    return
      self.projectFilter != .allProjects ||
      self.productionFilter ||
      self.stateFilter != .allStates
  }
}

struct DeploymentsListView_Previews: PreviewProvider {
  static var previews: some View {
    DeploymentsListView(teamID: "-1")
  }
}
