package edu.bu.ist.apps.aws.lambda;

import java.util.Properties;

import org.junit.FixMethodOrder;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.runners.MockitoJUnitRunner;

//@FixMethodOrder
//@RunWith(MockitoJUnitRunner.class)
public class PropertiesFileTest {
	
	//@Test
	public void test() {
		byte[] bytes = new byte[] {};
		PropertiesFile pf = new PropertiesFile(bytes);
		Properties p = pf.getProperties();
		
		// TODO: Make byte array and assert properties
	}

}
