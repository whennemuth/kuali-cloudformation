package org.bu.jenkins.job;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.mvc.controller.kuali.job.StackCreateDeleteController;

/**
 * There is one member of this enum for each Jenkins job there is whose fields are controlled by this service.
 * 
 * @author wrh
 *
 */
public enum Jobs {

	KUALI_STACK_CONTROLLER(StackCreateDeleteController.class.getName());
	
	private static Logger logger = LogManager.getLogger(AbstractJob.class.getName());
	
	private String className;
	
	Jobs(String className) {
		this.className = className;
	}
	
	public String className() {
		return className;
	}
	
	public static Class<?>  getClass(String jobInfo) {
		if(jobInfo == null) {
			return null;
		}
		
		Jobs job = null;
		String className = null;
		try {
			job = Jobs.valueOf(jobInfo.toUpperCase());
			className = job.className();
		} 
		catch (IllegalArgumentException e1) {
			className = jobInfo;
		}
		
		try {
			return Class.forName(className);
		} 
		catch (ClassNotFoundException e) {
			logger.error("No such class or enumeration: " + jobInfo, e);
			return null;
		}
	}
}
