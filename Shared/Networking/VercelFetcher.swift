//
//  VercelFetcher.swift
//  Zeitgeist
//
//  Created by Daniel Eden on 06/12/2020.
//  Copyright © 2020 Daniel Eden. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

let decoder = JSONDecoder()

enum FetcherError: Error {
  case decoding, fetching, updating
}

enum VercelRoute: String {
  case teams = "v1/teams"
  case deployments = "v6/now/deployments"
  case projects = "v6/projects"
  case user = "www/user"
}

public class VercelFetcher: ObservableObject {
  enum FetchState {
    case loading
    case finished
    case error
    case idle
  }
  
  static let shared: VercelFetcher = {
    print("Initialising")
    let instance = VercelFetcher(withTimer: true)
    return instance
  }()
  
  @Published var fetchState: FetchState = .idle
  
  @Published var teams: [VercelTeam] = [VercelTeam()]
  
  @Published var user: VercelUser?
  
  /**
   Since the deployments array is recycled across teams, it’s advisable to use self.deploymentsStore instead
   */
  @Published var deployments: [Deployment] = []
  
  @Published var deploymentsStore = DeploymentsStore()
  @Published var projectsStore = ProjectsStore()
  
  @ObservedObject var settings = Session.shared
  
  private var pollingTimer: Timer?
  
  init() {
    
  }
  
  init(withTimer: Bool) {
    if withTimer {
      resetTimers()
    }
  }
  
  deinit {
    resetTimers(reinit: false)
  }
  
  func resetTimers(reinit: Bool = true) {
    pollingTimer?.invalidate()
    pollingTimer = nil
    
    if reinit {
      pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [weak self] _ in
        self?.tick()
      })
      
      pollingTimer?.tolerance = 0.5
      RunLoop.current.add(pollingTimer!, forMode: .common)
      pollingTimer?.fire()
    }
  }
  
  func tick() {
    if self.settings.token != nil {
      self.loadUser()
      self.loadTeams()
      self.loadAllDeployments()
      self.loadAllProjects()
    } else {
      print("Awaiting authentication token...")
    }
  }
  
  func urlForRoute(_ route: VercelRoute, query: String? = nil) -> URL {
    return URL(string: "https://api.vercel.com/\(route.rawValue)\(query ?? "")")!
  }
  
  func loadTeams() {  
    self.loadTeams { [unowned self] (teams, error) in
      if let error = error { print(error) }
      
      if let teams = teams {
        DispatchQueue.main.async {
          let newTeams = [VercelTeam()] + teams
          
          if self.teams != newTeams {
            self.teams = newTeams
          }
        }
      } else {
        print("Found `nil` instead of teams array")
      }
    }
  }
  
  func loadTeams(completion: @escaping ([VercelTeam]?, Error?) -> Void) {
    var request = URLRequest(url: urlForRoute(.teams))
    request.allHTTPHeaderFields = getHeaders()
    URLSession.shared.dataTask(with: request) { (data, _, error) in
      do {
        guard let response = data else {
          print("Error fetching teams")
          if let fetchError = error {
            print(fetchError.localizedDescription)
          }
          return
        }
        let decodedData = try JSONDecoder().decode(VercelTeamsAPIResponse.self, from: response)
        DispatchQueue.main.async {
          completion(decodedData.teams, nil)
        }
      } catch {
        completion(nil, error)
        print("Error loading teams")
        print(error.localizedDescription)
      }
    }.resume()
  }
  
  func loadDeployments() {
    self.loadDeployments { [unowned self] (entries, error) in
      if let deployments = entries {
        DispatchQueue.main.async {
          self.deployments = deployments
        }
      }
      
      if let errorMessage = error?.localizedDescription {
        print(errorMessage)
      }
    }
  }
  
  func loadAllDeployments() {
    for team in teams {
      loadDeployments(teamId: team.id) { [unowned self] (entries, error) in
        if let deployments = entries {
          DispatchQueue.main.async {
            self.deploymentsStore.updateStore(forTeam: team.id, newValue: deployments)
          }
        }
        
        if let errorMessage = error?.localizedDescription {
          print(errorMessage)
        }
      }
    }
  }
  
  func loadAllProjects() {
    for team in teams {
      loadProjects(teamId: team.id) { [unowned self] (entries, error) in
        if let projects = entries {
          DispatchQueue.main.async {
            self.projectsStore.updateStore(forTeam: team.id, newValue: projects)
          }
        }
        
        if let errorMessage = error?.localizedDescription {
          print(errorMessage)
        }
      }
    }
  }
  
  func loadProjects(teamId: String? = nil, completion: @escaping ([Project]?, Error?) -> Void) {
    let unmaskedTeamId = teamId == "-1" ? "" : teamId ?? ""
    var request = URLRequest(url: urlForRoute(.projects, query: "?teamId=\(unmaskedTeamId)"))
    
    request.allHTTPHeaderFields = getHeaders()
    
    URLSession.shared.dataTask(with: request) { (data, _, error) in
      if let data = data {
        do {
          let response = try decoder.decode(ProjectResponse.self, from: data)
          
          completion(response.projects, nil)
        } catch {
          print("error: ", error)
        }
      } else {
        print("Error loading projects")
        return
      }
    }.resume()
    
    self.objectWillChange.send()
  }
  
  func loadDeployments(teamId: String? = nil, completion: @escaping ([Deployment]?, Error?) -> Void) {
    fetchState = deployments.isEmpty ? .loading : .idle
    let unmaskedTeamId = teamId == "-1" ? "" : teamId ?? ""
    var request = URLRequest(url: urlForRoute(.deployments, query: "?teamId=\(unmaskedTeamId)&limit=100"))
    
    request.allHTTPHeaderFields = getHeaders()
    
    URLSession.shared.dataTask(with: request) { (data, _, error) in
      if let data = data {
        do {
          let response = try decoder.decode(DeploymentResponse.self, from: data)
          DispatchQueue.main.async { [unowned self] in
            self.fetchState = .finished
          }
          completion(response.deployments, nil)
        } catch {
          print("error: ", error)
        }
      } else {
        print("Error loading deployments")
        return
      }
    }.resume()
    
    self.objectWillChange.send()
  }
  
  func loadAliases(deploymentId: String, completion: @escaping ([Alias]?, Error?) -> Void) {
    var request = URLRequest(url: urlForRoute(.deployments, query: "/\(deploymentId)/aliases"))
    
    request.allHTTPHeaderFields = getHeaders()
    
    URLSession.shared.dataTask(with: request) { (data, _, error) in
      if let data = data {
        do {
          let response = try decoder.decode(AliasesResponse.self, from: data)
          DispatchQueue.main.async { [weak self] in
            self?.fetchState = .finished
          }
          completion(response.aliases, nil)
        } catch {
          print("error: ", error)
        }
      } else {
        print("Error loading aliases")
        return
      }
    }.resume()
  }
  
  func loadUser() {
    var request = URLRequest(url: urlForRoute(.user))
    
    request.allHTTPHeaderFields = getHeaders()
    URLSession.shared.dataTask(with: request) { [unowned self] (data, _, error) in
      if data == nil {
        print("Error loading user")
        return
      }
      
      do {
        let decodedData = try JSONDecoder().decode(VercelUserAPIResponse.self, from: data!)
        DispatchQueue.main.async { [unowned self] in
          self.user = decodedData.user
        }
      } catch {
        print("Error decoding user")
        print(error.localizedDescription)
      }
    }.resume()
    
    self.objectWillChange.send()
  }
  
  public func getHeaders() -> [String: String] {
    return [
      "Authorization": "Bearer " + (settings.token ?? ""),
      "Content-Type": "application/json",
      "User-Agent": "ZG Client \(APP_VERSION)"
    ]
  }
}
