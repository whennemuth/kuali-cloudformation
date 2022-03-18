package org.bu.jenkins.job.kuali;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.dao.RdsInstanceDAO;
import org.bu.jenkins.job.JobParameter;
import org.bu.jenkins.mvc.controller.job.kuali.StackCreateDeleteController.ParameterName;
import org.bu.jenkins.mvc.model.AbstractAwsResource;
import org.bu.jenkins.mvc.model.Landscape;
import org.bu.jenkins.mvc.model.RdsInstance;

public class RdsUtilities {

	private Logger logger = LogManager.getLogger(RdsUtilities.class.getName());
	
	private AWSCredentials credentials;
	private JobParameter jobParameter;
	
	public static enum RdsInstanceCollectionType {
		LIST_OF_RDS_INSTANCES,
		MAP_OF_RDS_INSTANCES_BY_BASELINE
	}
	
	public RdsUtilities(AWSCredentials credentials, JobParameter jobParameter) {
		this.credentials = credentials;
		this.jobParameter = jobParameter;
	}
	
	/**
	 * Search through the provided collection and return the arn of an RdsInstance whose baseline is found to 
	 * match the applicable landscape (may return the first arn found if no such match can be obtained)
	 *  
	 * @param parameterName
	 * @param collectionType
	 * @return
	 */
	public String getRdsArn(Object parameterName, RdsInstanceCollectionType collectionType) {
		return getRdsArn(parameterName, collectionType, false);
	}
	
	public String getRdsArn(Object parameterName, RdsInstanceCollectionType collectionType, boolean defaultValue) {
		switch(collectionType) {
		case LIST_OF_RDS_INSTANCES:
			return searchList(parameterName, null, defaultValue);
		case MAP_OF_RDS_INSTANCES_BY_BASELINE:
			return searchMap(parameterName, defaultValue);
		}
		return null;
	}
	
	/**
	 * Search through a list of RdsInstances for the arn of the first one whose baseline is found to match
	 * the applicable landscape. If no such match can be obtained and defaultValue==true, then return the arn of the first RdsInstance in the list.
	 */
	private String searchList(Object parameterName, List<RdsInstance> rdsInstances, boolean defaultValue) {
		EntryMessage m = logger.traceEntry("getRdsArnForLandscape(jobParameter.getName()={})", jobParameter.getName());
		
		String rdsArn = jobParameter.getOtherParmValue(parameterName);
		if(isEmpty(rdsArn) && defaultValue) {
			if(rdsInstances == null) {
				rdsInstances = new ArrayList<RdsInstance>(new RdsInstanceDAO(credentials).getDeployedKualiRdsInstances());
			}
			
			rdsArn = new RdsItemSearch(jobParameter.getOtherParmValue(ParameterName.LANDSCAPE), jobParameter, rdsInstances.get(0).getArn()) {
				@Override public String getMatch(Object rds, String landscape) {
					AbstractAwsResource rdsInstance = (AbstractAwsResource) rds;
					if(landscape != null && landscape.equalsIgnoreCase(rdsInstance.getBaseline())) {
						return rdsInstance.getArn();
					}
					return null;
				}
				
			}.findItem(rdsInstances);
			
		}		
		
		logger.traceExit(m);
		return isEmpty(rdsArn) ? null : rdsArn;
	}
	
	/**
	 * Search through a map of RdsInstance lists, keyed by baseline for the arn of the first RdsInstance found under a key 
	 * that matches the applicable landscape. If no such match can be obtained, then return the arn of the first RdsInstance under any key.
	 * @param parameterName  The name of the parameter
	 * @param defaultValue If no match found return the first item of the map, else null.
	 * @return
	 */
	private String searchMap(Object parameterName, boolean defaultValue) {
		EntryMessage m = logger.traceEntry("getRdsArnForBaseline(jobParameter.getName()={})", jobParameter.getName());
		
		String rdsArn = jobParameter.getOtherParmValue(parameterName);
		if(rdsArn == null) {
			Map<Landscape, List<RdsInstance>> map = new RdsInstanceDAO(credentials).getDeployedKualiRdsInstancesGroupedByBaseline();
			rdsArn = searchList(parameterName, flattenMap(map), defaultValue);
		}
		
		logger.traceExit(m);
		return rdsArn;
	}
	
	private static List<RdsInstance> flattenMap(Map<Landscape, List<RdsInstance>> map) {
		List<RdsInstance> list = new ArrayList<RdsInstance>();
		if(map != null && ! map.isEmpty()) {
			for (Entry<Landscape, List<RdsInstance>> entry : map.entrySet()) {
				Landscape baseline = entry.getKey();
				for(RdsInstance rdsInstance : entry.getValue()) {
					list.add((RdsInstance) rdsInstance.setBaseline(baseline.getId()));
				}
			}
		}
		return list;
	}
	
	private static boolean isEmpty(String s) {
		if(s == null) return true;
		if("empty".equalsIgnoreCase(s)) return true;
		return false;
	}
	
	/**
	 * A class that applies the template design pattern to perform the general task of looping through a collection
	 * To find some string value. Clients implement the class to provide the criteria for a match.
	 * 
	 * @author wrh
	 *
	 */
	private static abstract class RdsItemSearch {
		private String landscape;
		private JobParameter jobParameter;
		private String defaultValue;
		public RdsItemSearch(String landscape, JobParameter jobParameter) {
			this.landscape = landscape;
			this.jobParameter = jobParameter;
		}
		public RdsItemSearch(String landscape, JobParameter jobParameter, String defaultValue) {
			this(landscape, jobParameter);
			this.defaultValue = defaultValue;
		}
		public String findItem(Collection<?> c) {
			String value = null;
			if(jobParameter.isBlank() && c.isEmpty() == false) {
				for (Iterator<?> iterator = c.iterator(); iterator.hasNext();) {
					Object o = (Object) iterator.next();
					value = getMatch(o, landscape);
					if(value != null) {
						break;
					}
				}				
			}
			return value == null ? defaultValue : value;
		}
		public abstract String getMatch(Object o, String landscape);
	}

}
