import Foundation

extension Storage {
	func selectedCertificate() -> CertificatePair? {
		let defaults = UserDefaults.standard
		let certificates = getAllCertificates()
		if let uuid = defaults.string(forKey: "feather.selectedCertUUID") {
			return certificates.first { $0.uuid == uuid }
		}
		let index = defaults.integer(forKey: "feather.selectedCert")
		guard certificates.indices.contains(index) else { return nil }
		let certificate = certificates[index]
		defaults.set(certificate.uuid, forKey: "feather.selectedCertUUID")
		return certificate
	}

	func selectCertificate(_ certificate: CertificatePair) {
		UserDefaults.standard.set(certificate.uuid, forKey: "feather.selectedCertUUID")
		if let index = getAllCertificates().firstIndex(where: { $0.uuid == certificate.uuid }) {
			UserDefaults.standard.set(index, forKey: "feather.selectedCert")
		}
	}
}
