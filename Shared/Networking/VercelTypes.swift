//
//  FetchVercelBuilds.swift
//  Zeitgeist
//
//  Created by Daniel Eden on 27/05/2020.
//  Copyright © 2020 Daniel Eden. All rights reserved.
//

import Foundation

struct VercelTeam: Decodable, Identifiable, Equatable {
  public var id: String = "-1"
  public var name: String = "Personal"
  public var avatar: String?
}

struct VercelUser: Decodable, Identifiable {
  public var id: String
  public var name: String
  public var email: String
  public var avatar: String
  
  enum CodingKeys: String, CodingKey {
    case id = "uid"
    
    case email, name, avatar
  }
}

struct VercelUserAPIResponse: Decodable {
  public var user: VercelUser
}

struct VercelTeamsAPIResponse: Decodable {
  public var teams: [VercelTeam] = []
}

struct DeploymentResponse: Decodable {
  public var deployments: [Deployment] = []
}

struct ProjectResponse: Decodable {
  public var projects: [Project] = []
}
