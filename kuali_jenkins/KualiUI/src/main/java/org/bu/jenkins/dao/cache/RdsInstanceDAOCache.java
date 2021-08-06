package org.bu.jenkins.dao.cache;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.mvc.model.AbstractAwsResource;
import org.bu.jenkins.mvc.model.RdsInstance;

/**
 * Store the return values of api calls for rds resource information so that repeat calls for the same or overlapping information need not be made.
 * This is a primary performance optimization.
 * 
 * @author wrh
 *
 */
public class RdsInstanceDAOCache extends BasicDAOCache {
	
	private Logger logger = LogManager.getLogger(RdsInstanceDAOCache.class.getName());
	
	@Override
	protected void performCustomPreCachingAction(AbstractAwsResource resource, AbstractAwsResource cachedResource) {
		RdsInstance rdsInstance = (RdsInstance) resource;
		RdsInstance cached = (RdsInstance) cachedResource;
		if(cached.getSnapshots().size() < rdsInstance.getSnapshots().size()) {
			cached.setSnapshots(rdsInstance.getSnapshots());
		}		
	}

	@Override
	protected Logger getLogger() {
		return logger;
	}
}
