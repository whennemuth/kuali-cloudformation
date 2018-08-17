package edu.bu.ist.apps.aws.task;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.junit.Before;
import org.junit.Test;

public class TaskResultTest {
	
	private List<String> logs = new ArrayList<String>();
	private static final String GOOD_CLASS = "edu.bu.ist.apps.aws.task.BasicOutputMask";
	
	@Before
	public void setup() {
		logs.clear();
	}
	
	// Represents the contents of a typical properties file
	private static String props = "LANDSCAPE=ci\r\n" + 
			"CORE_HOST=kuali-research-ci.bu.edu\r\n" + 
			"SHIB_HOST=shib-test.bu.edu\r\n" + 
			"BU_LOGOUT_URL=https://kuali-research-ci.bu.edu/Shibboleth.sso/Logout?return=https://shib-test.bu.edu/idp/logout.jsp\r\n" + 
			"UPDATE_INSTITUTION=false\r\n" + 
			"SMTP_HOST=smtp.bu.edu\r\n" + 
			"SMTP_PORT=25\r\n" + 
			"JOBS_SCHEDULER=true\r\n" + 
			"MONGO_URI=mongodb://ci-cluster-shard-00-00-nzjcq.mongodb.net:27017,ci-cluster-shard-00-01-nzjcq.mongodb.net:27017,ci-cluster-shard-00-02-nzjcq.mongodb.net:27017/core-development?replicaSet=ci-cluster-shard-0&ssl=true&authSource=admin\r\n" + 
			"MONGO_PRIMARY_SHARD=ci-cluster-shard-00-00-nzjcq.mongodb.net\r\n" + 
			"MONGO_USER=admin\r\n" + 
			"MONGO_PASS=mongo-password\r\n" + 
			"SERVICE_SECRET_1=cisharedsecret1\r\n" + 
			"AWS_ACCESS_KEY_ID=MY-ACCESS-KEY\r\n" + 
			"AWS_SECRET_ACCESS_KEY=MY-SECRET\r\n" + 
			"AWS_DEFAULT_REGION=us-east_1\r\n" + 
			"AWS_PROFILE=ecr.access\r\n" + 
			"# START_CMD=node --inspect /var/core/dist/index.js\r\n" + 
			"START_CMD=node --inspect /var/core/index.js\r\n" + 
			"KC_IDP_AUTH_REQUEST_URL=https://kuali-research-ci.bu.edu/Shibboleth.sso/SAML2/POST\r\n" + 
			"# KC_IDP_CALLBACK_OVERRIDE=some value\r\n" + 
			"# NODEAPP_BROWSER_PORT=8090\r\n" + 
			"# MONGO_URI=mongodb://localhost/core-development\r\n" + 
			"# MONGO_REPLICASET=ci-cluster-shard-0";
	
	private static String sblob = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aenean vel quam non augue aliquet dignissim "
			+ "volutpat eu nunc. Aliquam viverra ipsum sit amet erat tincidunt consequat. Sed convallis at ipsum quis fringilla. "
			+ "Fusce nec nibh finibus, vehicula tortor eu, pellentesque nulla. Suspendisse convallis rhoncus leo, sit amet "
			+ "euismod erat posuere ut. Phasellus molestie cursus erat ut euismod. Sed maximus purus dapibus justo finibus aliquet. "
			+ "Nam eget iaculis tortor. Maecenas sit amet faucibus sapien. Sed egestas justo eros, non vehicula neque eleifend at. "
			+ "Vestibulum at ligula sed metus hendrerit congue id quis erat. Donec faucibus dignissim nisl, quis lacinia orci "
			+ "iaculis id. Duis at dolor et tellus ultrices varius blandit sed lacus. Aenean convallis varius tincidunt. Morbi "
			+ "sed efficitur odio, et aliquam lorem.\r\n" + 
			"\r\n" + 
			"Phasellus id pharetra tellus, ac rhoncus odio. Mauris nulla ante, tempor et ipsum ut, iaculis tincidunt eros. "
			+ "Donec blandit leo tempus mi gravida cursus. Curabitur finibus est eu sapien cursus dignissim. Sed vitae erat "
			+ "non mi consectetur efficitur. Sed luctus dictum mi, non rutrum urna pharetra eget. Morbi sit amet neque lobortis "
			+ "risus laoreet vulputate eu at odio. Praesent lacinia augue at eros mollis, in egestas leo ultricies. In hac "
			+ "habitasse platea dictumst. Aenean posuere luctus viverra. Suspendisse tristique erat at lectus mollis, ut congue "
			+ "sem blandit. Ut vehicula fringilla ante, ut accumsan est tempor in. Nam et nibh tortor. In cursus egestas rutrum.\r\n" + 
			"\r\n" + 
			"Sed mauris mi, posuere a sagittis vel, tincidunt in nisi. Morbi tempus, purus quis pretium euismod, felis urna "
			+ "accumsan felis, id finibus sapien nisl ut est. Aenean posuere, nulla ut euismod placerat, odio diam tincidunt "
			+ "turpis, at lacinia ex orci vitae felis. Vivamus egestas augue sed rhoncus posuere. Donec ante ex, scelerisque vitae "
			+ "efficitur vel, accumsan non nulla. Sed ut ipsum convallis, convallis nibh ut, molestie magna. Praesent ultrices sem "
			+ "ligula. Quisque a sapien neque. Pellentesque aliquet ornare faucibus. Praesent hendrerit odio nec laoreet euismod. "
			+ "Ut pellentesque, libero eu tincidunt auctor, purus mi dapibus ligula, sed sodales nunc orci nec neque.";
	
	@Test
	public void testProperties() {
		
		TaskResult tr = TaskResult.getInstanceFromProperties(props.getBytes());
		Map<String, Object> map = null;
		for(int i=1; i<=2; i++) {
			if(i==1)
				map = tr.getMaskedResults();
			else
				map = tr.getMaskedResultsForLogging();
			
			assertNotNull(map);
			assertEquals(19, map.keySet().size());
			
			assertMember("LANDSCAPE", "ci", map);
			assertMember("CORE_HOST", "kuali-research-ci.bu.edu", map);
			assertMember("SHIB_HOST", "shib-test.bu.edu", map);
			assertMember("BU_LOGOUT_URL", "https://kuali-research-ci.bu.edu/Shibboleth.sso/Logout?return=https://shib-test.bu.edu/idp/logout.jsp", map);
			assertMember("UPDATE_INSTITUTION", "false", map);
			assertMember("SMTP_HOST", "smtp.bu.edu", map);
			assertMember("SMTP_PORT", "25", map);
			assertMember("JOBS_SCHEDULER", "true", map);
			assertMember("MONGO_URI", "mongodb://ci-cluster-shard-00-00-nzjcq.mongodb.net:27017,ci-cluster-shard-00-01-nzjcq.mongodb.net:27017,ci-cluster-shard-00-02-nzjcq.mongodb.net:27017/core-development?replicaSet=ci-cluster-shard-0&ssl=true&authSource=admin", map);
			assertMember("MONGO_PRIMARY_SHARD", "ci-cluster-shard-00-00-nzjcq.mongodb.net", map);
			assertMember("MONGO_USER", "admin", map);
			assertMember("MONGO_PASS", "mongo-password", map);
			assertMember("SERVICE_SECRET_1", "cisharedsecret1", map);
			assertMember("AWS_ACCESS_KEY_ID", "MY-ACCESS-KEY", map);
			assertMember("AWS_SECRET_ACCESS_KEY", "MY-SECRET", map);
			assertMember("AWS_DEFAULT_REGION", "us-east_1", map);
			assertMember("AWS_PROFILE", "ecr.access", map);
			assertMember("START_CMD", "node --inspect /var/core/index.js", map);
			assertMember("KC_IDP_AUTH_REQUEST_URL", "https://kuali-research-ci.bu.edu/Shibboleth.sso/SAML2/POST", map);
		}
	}
	
	@Test
	public void testMaskedProperties() {
		
		OutputMask outputmask = OutputMask.getInstance(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[  \r\n" + 
				"            \"AWS_ACCESS_KEY_ID\",\r\n" + 
				"            \"AWS_SECRET_ACCESS_KEY\",\r\n" + 
				"            \"MONGO_PASS\",\r\n" + 
				"            \"SERVICE_SECRET_1\"\r\n" + 
				"         ],\r\n" + 
				"         logs:[  \r\n" + 
				"            \"LANDSCAPE\",\r\n" + 
				"            \"SMTP_PORT\"\r\n" + 
				"         ]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), (String msg) -> { log(msg); } );
		
		TaskResult tr = TaskResult.getInstanceFromProperties(props.getBytes(), outputmask);
		Map<String, Object> map = tr.getMaskedResults();
		assertNotNull(map);
		assertEquals(19, map.keySet().size());
		
		assertMember("LANDSCAPE", "ci", map);
		assertMember("CORE_HOST", "kuali-research-ci.bu.edu", map);
		assertMember("SHIB_HOST", "shib-test.bu.edu", map);
		assertMember("BU_LOGOUT_URL", "https://kuali-research-ci.bu.edu/Shibboleth.sso/Logout?return=https://shib-test.bu.edu/idp/logout.jsp", map);
		assertMember("UPDATE_INSTITUTION", "false", map);
		assertMember("SMTP_HOST", "smtp.bu.edu", map);
		assertMember("SMTP_PORT", "25", map);
		assertMember("JOBS_SCHEDULER", "true", map);
		assertMember("MONGO_URI", "mongodb://ci-cluster-shard-00-00-nzjcq.mongodb.net:27017,ci-cluster-shard-00-01-nzjcq.mongodb.net:27017,ci-cluster-shard-00-02-nzjcq.mongodb.net:27017/core-development?replicaSet=ci-cluster-shard-0&ssl=true&authSource=admin", map);
		assertMember("MONGO_PRIMARY_SHARD", "ci-cluster-shard-00-00-nzjcq.mongodb.net", map);
		assertMember("MONGO_USER", "admin", map);
		assertMember("MONGO_PASS", "**************", map);
		assertMember("SERVICE_SECRET_1", "***************", map);
		assertMember("AWS_ACCESS_KEY_ID", "*************", map);
		assertMember("AWS_SECRET_ACCESS_KEY", "*********", map);
		assertMember("AWS_DEFAULT_REGION", "us-east_1", map);
		assertMember("AWS_PROFILE", "ecr.access", map);
		assertMember("START_CMD", "node --inspect /var/core/index.js", map);
		assertMember("KC_IDP_AUTH_REQUEST_URL", "https://kuali-research-ci.bu.edu/Shibboleth.sso/SAML2/POST", map);
		
		map = tr.getMaskedResultsForLogging();
		assertNotNull(map);
		
		assertEquals(19, map.keySet().size());		assertMember("LANDSCAPE", "**", map);
		assertMember("CORE_HOST", "kuali-research-ci.bu.edu", map);
		assertMember("SHIB_HOST", "shib-test.bu.edu", map);
		assertMember("BU_LOGOUT_URL", "https://kuali-research-ci.bu.edu/Shibboleth.sso/Logout?return=https://shib-test.bu.edu/idp/logout.jsp", map);
		assertMember("UPDATE_INSTITUTION", "false", map);
		assertMember("SMTP_HOST", "smtp.bu.edu", map);
		assertMember("SMTP_PORT", "**", map);
		assertMember("JOBS_SCHEDULER", "true", map);
		assertMember("MONGO_URI", "mongodb://ci-cluster-shard-00-00-nzjcq.mongodb.net:27017,ci-cluster-shard-00-01-nzjcq.mongodb.net:27017,ci-cluster-shard-00-02-nzjcq.mongodb.net:27017/core-development?replicaSet=ci-cluster-shard-0&ssl=true&authSource=admin", map);
		assertMember("MONGO_PRIMARY_SHARD", "ci-cluster-shard-00-00-nzjcq.mongodb.net", map);
		assertMember("MONGO_USER", "admin", map);
		assertMember("MONGO_PASS", "**************", map);
		assertMember("SERVICE_SECRET_1", "***************", map);
		assertMember("AWS_ACCESS_KEY_ID", "*************", map);
		assertMember("AWS_SECRET_ACCESS_KEY", "*********", map);
		assertMember("AWS_DEFAULT_REGION", "us-east_1", map);
		assertMember("AWS_PROFILE", "ecr.access", map);
		assertMember("START_CMD", "node --inspect /var/core/index.js", map);
		assertMember("KC_IDP_AUTH_REQUEST_URL", "https://kuali-research-ci.bu.edu/Shibboleth.sso/SAML2/POST", map);
	}

	@Test
	public void testBlob() {		
		TaskResult tr = TaskResult.getInstanceFromBlob(sblob.getBytes());
		
		Map<String, Object> map = tr.getMaskedResults();		
		assertNotNull(map);
		assertEquals(1, map.keySet().size());
		assertEquals(sblob, map.get("blob"));
		
		map = tr.getMaskedResultsForLogging();
		assertNotNull(map);
		assertEquals(1, map.keySet().size());
		assertEquals(sblob, map.get("blob"));
	}

	@Test
	public void testMaskedBlob() {		
		
		OutputMask outputmask = OutputMask.getInstance(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[],\r\n" + 
				"         logs:[all]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), (String msg) -> { log(msg); } );
		
		TaskResult tr = TaskResult.getInstanceFromBlob(sblob.getBytes(), outputmask);
		
		Map<String, Object> map = tr.getMaskedResultsForLogging();
		assertNotNull(map);
		assertEquals(1, map.keySet().size());
		String blobstr = (String) map.get("blob");
		assertEquals(sblob.length(), blobstr.length());
		assertTrue(blobstr.matches("^\\*{" + String.valueOf(sblob.length()) + "}$"));
		
		map = tr.getMaskedResults();
		assertNotNull(map);
		assertEquals(1, map.keySet().size());
		assertEquals(sblob, map.get("blob"));
		
		
		outputmask = OutputMask.getInstance(String.format("{  \r\n" + 
				"   class: %s,\r\n" + 
				"   parameters:{  \r\n" + 
				"      fieldsToMask:{  \r\n" + 
				"         full:[all],\r\n" + 
				"         logs:[]\r\n" + 
				"      }\r\n" + 
				"   }\r\n" + 
				"}", GOOD_CLASS), (String msg) -> { log(msg); } );
		
		tr = TaskResult.getInstanceFromBlob(sblob.getBytes(), outputmask);
		
		map = tr.getMaskedResultsForLogging();
		assertNotNull(map);
		assertEquals(1, map.keySet().size());
		blobstr = (String) map.get("blob");
		assertEquals(sblob.length(), blobstr.length());
		assertTrue(blobstr.matches("^\\*{" + String.valueOf(sblob.length()) + "}$"));
		
		map = tr.getMaskedResults();
		assertNotNull(map);
		assertEquals(1, map.keySet().size());
		blobstr = (String) map.get("blob");
		assertEquals(sblob.length(), blobstr.length());
		assertTrue(blobstr.matches("^\\*{" + String.valueOf(sblob.length()) + "}$"));
	}
	
	private void assertMember(String key, String value, Map<String, Object> map) {
		assertTrue(map.containsKey(key));
		assertEquals(value, map.get(key));		
	}
	
	private void log(String msg) {
		System.out.println(msg);
		logs.add(msg);
	}

}
