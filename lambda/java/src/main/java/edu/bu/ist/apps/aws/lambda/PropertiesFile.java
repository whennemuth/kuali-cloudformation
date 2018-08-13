package edu.bu.ist.apps.aws.lambda;

import java.util.Properties;

public class PropertiesFile {

	private byte[] bytes;
	private Properties properties;
	
	public PropertiesFile(byte[] bytes) {
		this.bytes = bytes;
	}

	public Properties getProperties() {
		if(properties == null) {
			// RESUME NEXT: Code for this.
		}
		return properties;
	}

	public static void main(String[] args) {
		// TODO Auto-generated method stub

	}
}
