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

public class VercelFetcher: ObservableObject {
  static let shared = VercelFetcher(UserDefaultsManager.shared)
  
  @Published var fetchState: FetchState = .idle {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.objectWillChange.send()
      }
    }
  }
  
  @Published var teams = [VercelTeam]() {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.objectWillChange.send()
      }
    }
  }
  
  @Published var deployments = [Deployment]() {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.objectWillChange.send()
      }
    }
  }
  
  @Published var user: VercelUser? {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.objectWillChange.send()
      }
    }
  }
  
  @ObservedObject var settings: UserDefaultsManager
  
  var teamId: String? {
    didSet {
      self.fetchState = .loading
      resetTimers()
      self.objectWillChange.send()
    }
  }
  
  private var pollingTimer: Timer?
  
  init(_ settings: UserDefaultsManager) {
    self.settings = settings
  }
  
  init(_ settings: UserDefaultsManager, withTimer: Bool) {
    self.settings = settings
    self.loadUser()
    
    if withTimer {
      resetTimers()
    }
  }
  
  deinit {
    resetTimers(reinit: false)
  }
  
  func resetTimers(reinit: Bool = true) {
    deployments = [Deployment]()
    pollingTimer?.invalidate()
    pollingTimer = nil
    
    if reinit {
      pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [weak self] _ in
        self?.loadDeployments()
        self?.loadTeams()
      })
      
      pollingTimer?.tolerance = 0.5
      RunLoop.current.add(pollingTimer!, forMode: .common)
      pollingTimer?.fire()
    }
  }
  
  func urlForRoute(_ route: VercelRoute, query: String? = nil) -> URL {
    return URL(string: "https://api.vercel.com/\(route.rawValue)\(query ?? "")")!
  }
  
  func loadTeams() {
    self.loadTeams { [weak self] (teams, error) in
      if error != nil { print(error!) }
      
      if teams != nil {
        DispatchQueue.main.async {
          self?.teams = teams!
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
          print("error")
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
    self.loadDeployments { [weak self] (entries, error) in
      if let deployments = entries {
        DispatchQueue.main.async {
          self?.deployments = deployments
        }
      }
      
      if let errorMessage = error?.localizedDescription {
        print(errorMessage)
      }
    }
  }
  
  func loadDeployments(completion: @escaping ([Deployment]?, Error?) -> Void) {
    fetchState = deployments.isEmpty ? .loading : .idle
    var request = URLRequest(url: urlForRoute(.deployments, query: "?teamId=\(getTeamId() ?? "")"))
    
    request.allHTTPHeaderFields = getHeaders()
    
    URLSession.shared.dataTask(with: request) { (data, _, error) in
      if data == nil {
        print("Error loading deployments")
        return
      }
      
      do {
        // swiftlint:disable force_cast
        if let serialised = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any],
           let _deployments = (serialised["deployments"] as? [[String: Any]]) {
          let deployments = _deployments.map { (deployment: [String: Any]) -> Deployment in
            let _creator = deployment["creator"] as! [String: String]
            let creator = VercelDeploymentUser(
              id: _creator["uid"]!,
              email: _creator["email"]!,
              username: _creator["username"]!
            )
            
            return Deployment(
              project: deployment["name"] as! String,
              id: deployment["uid"] as! String,
              createdAt: Date(timeIntervalSince1970: TimeInterval(deployment["created"] as! Int / 1000)),
              state: DeploymentState(rawValue: deployment["state"] as! String)!,
              url: URL(string: "https://\(deployment["url"] as! String)")!,
              creator: creator,
              svnInfo: GitCommit.from(json: deployment["meta"] as! [String: String])
            )
          }
          
          DispatchQueue.main.async { [weak self] in
            self?.fetchState = .finished
          }
          
          completion(deployments, nil)
        }
      } catch let error as NSError {
        print("Error decoding deployments")
        print(error.localizedDescription)
        
        DispatchQueue.main.async { [weak self] in
          self?.fetchState = .error
        }
        
        completion(nil, error)
      }
    }.resume()
    
    self.objectWillChange.send()
  }
  
  func loadUser() {
    var request = URLRequest(url: urlForRoute(.user))
    
    request.allHTTPHeaderFields = getHeaders()
    URLSession.shared.dataTask(with: request) { [weak self] (data, _, error) in
      if data == nil {
        print("Error loading user")
        return
      }
      
      do {
        let decodedData = try JSONDecoder().decode(VercelUserAPIResponse.self, from: data!)
        DispatchQueue.main.async { [weak self] in
          self?.user = decodedData.user
        }
      } catch {
        print("Error decoding user")
        print(error.localizedDescription)
        DispatchQueue.main.async { [weak self] in
          self?.fetchState = .error
        }
      }
    }.resume()
    
    self.objectWillChange.send()
  }
  
  func getTeamId() -> String? {
    return self.settings.currentTeam
  }
  
  public func getHeaders() -> [String: String] {
    return [
      "Authorization": "Bearer " + (settings.token ?? ""),
      "Content-Type": "application/json",
      "User-Agent": "ZG Client \(APP_VERSION)"
    ]
  }
}