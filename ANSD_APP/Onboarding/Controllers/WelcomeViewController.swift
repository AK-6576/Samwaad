//
//  WelcomeViewController.swift
//  ANSD_APP
//
//  Created by Dhiraj Bodake on 19/02/26.
//  Copyright © 2025 MIT-WPU Group 4. All rights reserved.
//

import UIKit
import GoogleSignIn
import FirebaseAuth
import AuthenticationServices

class WelcomeViewController: UIViewController, UITextFieldDelegate {

    // MARK: - Outlets
//    @IBOutlet weak var logoImageView: UIImageView!
    @IBOutlet weak var appleSignInButton: UIButton!
    @IBOutlet weak var googleSignInButton: UIButton!
    @IBOutlet weak var signupLabel: UILabel!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var forgotPasswordButton: UIButton!

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupKeyboardDismiss()
        registerKeyboardNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        // Text field styling - rounded corners with subtle border
        let textFields = [emailTextField, passwordTextField]
        for textField in textFields {
            textField?.layer.cornerRadius = 12
            textField?.layer.borderWidth = 1
            textField?.layer.borderColor = UIColor.systemGray4.cgColor
            textField?.clipsToBounds = true
            textField?.delegate = self
        }

        // Ensure Google icon is sized correctly without overriding storyboard layout
        if let googleIcon = UIImage(named: "Google")?.withRenderingMode(.alwaysOriginal) {
            let resizedIcon = googleIcon.resized(to: CGSize(width: 24, height: 24))
            googleSignInButton.configuration?.image = resizedIcon
        }

        // Sign In button styling - capsule
        loginButton.layer.cornerRadius = 28
        loginButton.clipsToBounds = true

        loginButton.setTitle("Sign In", for: .normal)

        // Fix text field alignments and colors
        emailTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 52))
        emailTextField.leftViewMode = .always
        passwordTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 52))
        passwordTextField.leftViewMode = .always

        emailTextField.textColor = .label
        passwordTextField.textColor = .label

        appleSignInButton.tintAdjustmentMode = .normal
        googleSignInButton.tintAdjustmentMode = .normal

        // Signup label attributed text
        setupSignupLabel()
    }

    private func setupSignupLabel() {
        let fullText = "Don't have an account yet? Create Now"
        let attributedString = NSMutableAttributedString(string: fullText)
        let fullRange = NSRange(location: 0, length: fullText.count)

        // Default style: black label color, system font 14
        attributedString.addAttribute(.foregroundColor, value: UIColor.black, range: fullRange)
        attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 14), range: fullRange)

        // "Signup Now" in blue
        if let signupRange = fullText.range(of: "Create Now") {
            let nsRange = NSRange(signupRange, in: fullText)
            attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: nsRange)
            attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 14, weight: .semibold), range: nsRange)
        }

        signupLabel.attributedText = attributedString
        signupLabel.textAlignment = .center
        signupLabel.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(signupLabelTapped(_:)))
        signupLabel.addGestureRecognizer(tap)
    }

    // MARK: - Actions
    @IBAction func appleSignInTapped(_ sender: UIButton) {
        appleSignInButton.isEnabled = false

        let hashedNonce = FirebaseManager.shared.generateNonce()

        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    @IBAction func googleSignInTapped(_ sender: UIButton) {
        // Show loading if possible (optional, but good practice)
        googleSignInButton.isEnabled = false

        FirebaseManager.shared.signInWithGoogle(presenting: self) { [weak self] result in
            DispatchQueue.main.async {
                self?.googleSignInButton.isEnabled = true

                switch result {
                case .success(let (user, isNewUser)):
                    self?.restoreUserAndNavigate(user: user, isNewUser: isNewUser)

                case .failure(let error):
                    self?.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func restoreUserAndNavigate(user: User, isNewUser: Bool) {
        let uid = user.uid

        // 1. Set Google/Firebase Auth Profile as baseline
        if let displayName = user.displayName, !displayName.isEmpty {
            let components = displayName.components(separatedBy: " ")
            if let first = components.first, !first.isEmpty {
                ProfileManager.shared.firstName = first
            }
            if components.count > 1 {
                let last = components.dropFirst().joined(separator: " ")
                ProfileManager.shared.lastName = last
            }
        }
        
        // Load profile picture
        if let photoURL = user.photoURL {
            URLSession.shared.dataTask(with: photoURL) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        ProfileManager.shared.profileImage = image
                    }
                }
            }.resume()
        }

        // 2. Fetch user profile from Realtime Database (to override with any user customizations)
        FirebaseManager.shared.fetchUserProfile(uid: uid) { profileData in
            DispatchQueue.main.async {
                if let data = profileData {
                    let firstName = data["firstName"] as? String ?? ""
                    let lastName = data["lastName"] as? String ?? ""
                    if !firstName.isEmpty {
                        ProfileManager.shared.firstName = firstName
                    }
                    if !lastName.isEmpty {
                        ProfileManager.shared.lastName = lastName
                    }
                }

                // Restore conversation history
                FirebaseManager.shared.fetchConversationHistory(uid: uid) { conversations in
                    DispatchQueue.main.async {
                        for dict in conversations {
                            guard let id = dict["id"] as? String,
                                  let title = dict["title"] as? String else { continue }

                            // Skip if already exists locally
                            if DataManager.shared.fetchConversation(byId: id) != nil { continue }

                            // Fetch FULL DATA (Messages + Participants)
                            FirebaseManager.shared.fetchFullConversation(uid: uid, conversationID: id) { fullData in
                                DispatchQueue.main.async {
                                    let metadata = fullData?["metadata"] as? [String: Any] ?? dict
                                    let participantsDict = fullData?["participants"] as? [String: [String: Any]] ?? [:]
                                    let messagesDict = fullData?["messages"] as? [String: [String: Any]] ?? [:]

                                    // 1. Create Participants
                                    var historyParticipants: [Participant] = []
                                    for (_, pData) in participantsDict {
                                        let p = Participant(
                                            name: pData["name"] as? String ?? "Unknown",
                                            summary: pData["summary"] as? String ?? "",
                                            image: pData["image"] as? String ?? "person.circle.fill"
                                        )
                                        historyParticipants.append(p)
                                    }

                                    // 2. Create Messages
                                    var historyMessages: [Message] = []
                                    for (_, mData) in messagesDict {
                                        let m = Message(
                                            id: UUID(),
                                            text: mData["text"] as? String ?? "",
                                            senderId: mData["senderId"] as? String ?? "",
                                            senderName: mData["senderName"] as? String ?? "",
                                            isIncoming: mData["isIncoming"] as? Bool ?? false,
                                            timestamp: Date(timeIntervalSince1970: mData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970),
                                            isHighlighted: mData["isHighlighted"] as? Bool ?? false,
                                            isEdited: mData["isEdited"] as? Bool ?? false
                                        )
                                        historyMessages.append(m)
                                    }

                                    // 3. Create Conversation
                                    let convo = Conversation(
                                        id: id,
                                        title: title,
                                        details: metadata["details"] as? String ?? "",
                                        date: metadata["date"] as? String ?? "",
                                        startTime: metadata["startTime"] as? String ?? "",
                                        endTime: metadata["endTime"] as? String ?? "",
                                        location: metadata["location"] as? String ?? "",
                                        category: metadata["category"] as? String ?? "",
                                        icon: metadata["icon"] as? String ?? "",
                                        info: metadata["info"] as? Bool,
                                        calendarDate: Date(timeIntervalSince1970: metadata["calendarDate"] as? TimeInterval ?? Date().timeIntervalSince1970),
                                        notes: metadata["notes"] as? String,
                                        isPinned: metadata["isPinned"] as? Bool ?? false,
                                        ownerUID: uid,
                                        participants: historyParticipants,
                                        messages: historyMessages
                                    )

                                    DataManager.shared.addConversation(convo)
                                }
                            }
                        }

                        // Restore Quick Actions
                        FirebaseManager.shared.fetchQuickActions(uid: uid) { actions in
                            DispatchQueue.main.async {
                                for dict in actions {
                                    guard let id = dict["id"] as? String,
                                          let categoryTitle = dict["categoryTitle"] as? String,
                                          let conversationTopic = dict["conversationTopic"] as? String,
                                          let startTime = dict["startTime"] as? String,
                                          let status = dict["status"] as? String,
                                          let roomCode = dict["roomCode"] as? String,
                                          let iconName = dict["iconName"] as? String,
                                          let topicImage = dict["topicImage"] as? String,
                                          let timeImage = dict["timeImage"] as? String else { continue }

                                    let existing = QuickActionsRepository.shared.getAllActions()
                                    if existing.contains(where: { $0.id == id }) { continue }

                                    let action = RoutineConversation(
                                        id: id,
                                        iconName: iconName,
                                        categoryTitle: categoryTitle,
                                        status: status,
                                        conversationTopic: conversationTopic,
                                        topicImage: topicImage,
                                        startTime: startTime,
                                        description: dict["description"] as? String,
                                        date: dict["date"] as? String,
                                        timeImage: timeImage,
                                        roomCode: roomCode,
                                        participantNames: dict["participantNames"] as? [String] ?? []
                                    )
                                    QuickActionsRepository.shared.addAction(action)
                                }

                                // Handle navigation based on user status
                                DispatchQueue.main.async {
                                    if isNewUser || VoiceProfileManager.shared.getVoiceProfile(byUID: uid) == nil {
                                        self.performSegue(withIdentifier: "showCalibrationFromWelcome", sender: self)
                                    } else {
                                        self.performSegue(withIdentifier: "googleSignInToHome", sender: self)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func signupLabelTapped(_ gesture: UITapGestureRecognizer) {
        guard let text = signupLabel.text,
              let range = text.range(of: "Create Now") else { return }

        let nsRange = NSRange(range, in: text)
        let tapLocation = gesture.location(in: signupLabel)

        // Use text storage to check if tap is within "Signup Now" range
        let textStorage = NSTextStorage(attributedString: signupLabel.attributedText ?? NSAttributedString(string: text))
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: signupLabel.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = signupLabel.numberOfLines
        textContainer.lineBreakMode = signupLabel.lineBreakMode

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let characterIndex = layoutManager.characterIndex(for: tapLocation, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

        if NSLocationInRange(characterIndex, nsRange) {
            performSegue(withIdentifier: "showCreateAccount", sender: self)
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == emailTextField {
            passwordTextField.becomeFirstResponder()
        } else if textField == passwordTextField {
            passwordTextField.resignFirstResponder()
            loginTapped(loginButton)
        }
        return true
    }

    // MARK: - Actions

    @IBAction func loginTapped(_ sender: UIButton) {
        // Dismiss keyboard
        view.endEditing(true)

        // Validation
        guard let email = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            showAlert(title: "Missing Field", message: "Please enter your email address.")
            return
        }

        guard let password = passwordTextField.text, !password.isEmpty else {
            showAlert(title: "Missing Field", message: "Please enter your password.")
            return
        }

        // Show loading state
        loginButton.isEnabled = false
        loginButton.configuration?.showsActivityIndicator = true

        let details = ["email": email, "password": password]

        // Firebase login
        FirebaseManager.shared.loginUser(details: details) { [weak self] result in
            DispatchQueue.main.async {
                self?.loginButton.isEnabled = true
                self?.loginButton.configuration?.showsActivityIndicator = false

                switch result {
                case .success(let user):
                    let uid = user.uid
                    
                    // 1. Set Google/Firebase Auth Profile as baseline
                    if let displayName = user.displayName, !displayName.isEmpty {
                        let components = displayName.components(separatedBy: " ")
                        if let first = components.first, !first.isEmpty {
                            ProfileManager.shared.firstName = first
                        }
                        if components.count > 1 {
                            let last = components.dropFirst().joined(separator: " ")
                            ProfileManager.shared.lastName = last
                        }
                    }
                    
                    // Load profile picture
                    if let photoURL = user.photoURL {
                        URLSession.shared.dataTask(with: photoURL) { data, _, _ in
                            if let data = data, let image = UIImage(data: data) {
                                DispatchQueue.main.async {
                                    ProfileManager.shared.profileImage = image
                                }
                            }
                        }.resume()
                    }

                    // 2. Fetch user profile
                    FirebaseManager.shared.fetchUserProfile(uid: uid) { profileData in
                        DispatchQueue.main.async {
                            if let data = profileData {
                                let firstName = data["firstName"] as? String ?? ""
                                let lastName = data["lastName"] as? String ?? ""
                                if !firstName.isEmpty {
                                    ProfileManager.shared.firstName = firstName
                                }
                                if !lastName.isEmpty {
                                    ProfileManager.shared.lastName = lastName
                                }
                            } else {
                                // Fallback to email prefix if profile data is not available and displayName was empty
                                if ProfileManager.shared.firstName.isEmpty {
                                    let emailPrefix = email.components(separatedBy: "@").first ?? ""
                                    let firstName = emailPrefix.components(separatedBy: ".").first?.capitalized ?? emailPrefix
                                    if !firstName.isEmpty {
                                        ProfileManager.shared.firstName = firstName
                                    }
                                }
                            }

                            // Restore conversation history
                            FirebaseManager.shared.fetchConversationHistory(uid: uid) { conversations in
                                DispatchQueue.main.async {
                                    for dict in conversations {
                                        guard let id = dict["id"] as? String,
                                              let title = dict["title"] as? String else { continue }

                                        // Skip if conversation already exists locally
                                        if DataManager.shared.fetchConversation(byId: id) != nil { continue }

                                        // Fetch FULL DATA (Messages + Participants)
                                        FirebaseManager.shared.fetchFullConversation(uid: uid, conversationID: id) { fullData in
                                            DispatchQueue.main.async {
                                                let metadata = fullData?["metadata"] as? [String: Any] ?? dict
                                                let participantsDict = fullData?["participants"] as? [String: [String: Any]] ?? [:]
                                                let messagesDict = fullData?["messages"] as? [String: [String: Any]] ?? [:]

                                                // 1. Create Participants
                                                var historyParticipants: [Participant] = []
                                                for (_, pData) in participantsDict {
                                                    let p = Participant(
                                                        name: pData["name"] as? String ?? "Unknown",
                                                        summary: pData["summary"] as? String ?? "",
                                                        image: pData["image"] as? String ?? "person.circle.fill"
                                                    )
                                                    historyParticipants.append(p)
                                                }

                                                // 2. Create Messages
                                                var historyMessages: [Message] = []
                                                for (_, mData) in messagesDict {
                                                    let m = Message(
                                                        id: UUID(),
                                                        text: mData["text"] as? String ?? "",
                                                        senderId: mData["senderId"] as? String ?? "",
                                                        senderName: mData["senderName"] as? String ?? "",
                                                        isIncoming: mData["isIncoming"] as? Bool ?? false,
                                                        timestamp: Date(timeIntervalSince1970: mData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970),
                                                        isHighlighted: mData["isHighlighted"] as? Bool ?? false,
                                                        isEdited: mData["isEdited"] as? Bool ?? false
                                                    )
                                                    historyMessages.append(m)
                                                }

                                                // 3. Create Conversation
                                                let convo = Conversation(
                                                    id: id,
                                                    title: title,
                                                    details: metadata["details"] as? String ?? "",
                                                    date: metadata["date"] as? String ?? "",
                                                    startTime: metadata["startTime"] as? String ?? "",
                                                    endTime: metadata["endTime"] as? String ?? "",
                                                    location: metadata["location"] as? String ?? "",
                                                    category: metadata["category"] as? String ?? "",
                                                    icon: metadata["icon"] as? String ?? "",
                                                    info: metadata["info"] as? Bool,
                                                    calendarDate: Date(timeIntervalSince1970: metadata["calendarDate"] as? TimeInterval ?? Date().timeIntervalSince1970),
                                                    notes: metadata["notes"] as? String,
                                                    isPinned: metadata["isPinned"] as? Bool ?? false,
                                                    ownerUID: uid,
                                                    participants: historyParticipants,
                                                    messages: historyMessages
                                                )

                                                DataManager.shared.addConversation(convo)
                                            }
                                        }
                                    }

                                    // Restore Quick Actions
                                    FirebaseManager.shared.fetchQuickActions(uid: uid) { actions in
                                        DispatchQueue.main.async {
                                            for dict in actions {
                                                guard let id = dict["id"] as? String,
                                                      let categoryTitle = dict["categoryTitle"] as? String,
                                                      let conversationTopic = dict["conversationTopic"] as? String,
                                                      let startTime = dict["startTime"] as? String,
                                                      let status = dict["status"] as? String,
                                                      let roomCode = dict["roomCode"] as? String,
                                                      let iconName = dict["iconName"] as? String,
                                                      let topicImage = dict["topicImage"] as? String,
                                                      let timeImage = dict["timeImage"] as? String else { continue }

                                                let existing = QuickActionsRepository.shared.getAllActions()
                                                if existing.contains(where: { $0.id == id }) { continue }

                                                let action = RoutineConversation(
                                                    id: id,
                                                    iconName: iconName,
                                                    categoryTitle: categoryTitle,
                                                    status: status,
                                                    conversationTopic: conversationTopic,
                                                    topicImage: topicImage,
                                                    startTime: startTime,
                                                    description: dict["description"] as? String,
                                                    date: dict["date"] as? String,
                                                    timeImage: timeImage,
                                                    roomCode: roomCode,
                                                    participantNames: dict["participantNames"] as? [String] ?? []
                                                )
                                                QuickActionsRepository.shared.addAction(action)
                                            }

                                            DispatchQueue.main.async {
                                                // Navigate to Home by resetting the window root for a clean state
                                                let storyboard = UIStoryboard(name: "Home", bundle: nil)
                                                if let homeNav = storyboard.instantiateViewController(withIdentifier: "HomeNav") as? UINavigationController {
                                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                                       let window = windowScene.windows.first {
                                                        window.rootViewController = homeNav
                                                        window.makeKeyAndVisible()
                                                        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil, completion: nil)
                                                    } else {
                                                        // Fallback to modal presentation if window lookup fails
                                                        homeNav.modalPresentationStyle = .fullScreen
                                                        self?.present(homeNav, animated: true, completion: nil)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                case .failure(let error):
                    self?.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @IBAction func forgotPasswordTapped(_ sender: UIButton) {
        // The segue "showForgotPassword" is already triggered via storyboard connection,
        // so we don't need to perform it programmatically here to avoid a double push.
    }
}

// MARK: - UIImage Extension
extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Apple Sign-In Delegates
extension WelcomeViewController: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let rawNonce = FirebaseManager.shared.currentNonce else {
            DispatchQueue.main.async { self.appleSignInButton.isEnabled = true }
            showAlert(title: "Sign In Failed", message: "Apple credential or nonce was missing.")
            return
        }

        FirebaseManager.shared.completeAppleSignIn(
            credential: appleCredential,
            rawNonce: rawNonce
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.appleSignInButton.isEnabled = true

                switch result {
                case .success(let (user, isNewUser)):
                    self?.restoreUserAndNavigate(user: user, isNewUser: isNewUser)

                case .failure(let error):
                    self?.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            self.appleSignInButton.isEnabled = true
            // ASAuthorizationError.canceled (code 1001) means the user dismissed the sheet — no alert needed.
            if (error as? ASAuthorizationError)?.code != .canceled {
                self.showAlert(title: "Sign In Failed", message: error.localizedDescription)
            }
        }
    }
}

extension WelcomeViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return view.window!
    }
}

// MARK: - Keyboard Handling
extension WelcomeViewController {
    private func setupKeyboardDismiss() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        // Reset transform to calculate correct bounds
        self.view.transform = .identity

        let bottomOfLoginButton = loginButton.convert(loginButton.bounds, to: self.view).maxY
        let topOfKeyboard = self.view.frame.height - keyboardFrame.height

        if bottomOfLoginButton > topOfKeyboard {
            let shiftAmount = bottomOfLoginButton - topOfKeyboard + 20
            UIView.animate(withDuration: 0.3) {
                self.view.transform = CGAffineTransform(translationX: 0, y: -shiftAmount)
            }
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.view.transform = .identity
        }
    }
}
