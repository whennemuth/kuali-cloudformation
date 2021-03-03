package org.bu.jenkins.job.kuali;

import java.net.URLDecoder;
import java.nio.charset.Charset;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.NamedArgs;
import org.bu.jenkins.SimpleHttpHandler;
import org.bu.jenkins.active_choices.html.AbstractParameterView;
import org.bu.jenkins.active_choices.model.LandscapeList;
import org.bu.jenkins.active_choices.model.RdsSnapshot;
import org.bu.jenkins.active_choices.model.StackList;
import org.bu.jenkins.job.AbstractJob;
import org.bu.jenkins.job.JobParameterMetadata;
import org.bu.jenkins.job.JobParameterConfiguration;
import org.bu.jenkins.job.JobParameter;

/**
 * This class is associated with the jenkins job used to create and delete application stacks for Kuali.
 * It is primarily concerned with generating the html behind any of the active choices parameters in that job.
 * 
 * @author wrh
 *
 */
public class StackCreateDelete extends AbstractJob {
	
	
	public StackCreateDelete(AWSCredentials credentials) {		
		this.credentials = credentials;
	}
	
	public StackCreateDelete() {
		this.credentials = new AWSCredentials();
	}
	
	public static enum ParameterName implements JobParameterMetadata {
		STACK("StackListTable", "stack-list-table"),
		STACK_ACTION("StackAction", "stack-action"),
		STACK_TYPE("StackType", "stack-type"),
		BASELINE("Baseline", "baseline"),
		LANDSCAPE("Landscape", "landscape"),
		AUTHENTICATION("Authentication", "authentication"),
		DNS("DNS", "dns"),
		WAF("WAF", "waf"),
		ALB("ALB", "alb"),
		RDS_CLONE_LANDSCAPE("RDS", "rds"),
		RDS_SNAPSHOT("RDS", "rds-snapshot"),
		MONGO("Mongo", "mongo"),
		value("Value", "value");
		
		private String viewName;
		private String templateSelector;
		
		ParameterName(String viewName, String templateSelector) {
			this.viewName = viewName;
			this.templateSelector = templateSelector;
		}
		@Override
		public String getViewName() {
			return viewName;
		}
		@Override
		public String getTemplateSelector() {
			return templateSelector;
		}		
	}

	@Override
	public JobParameterMetadata[] getJobParameterMetadata() {
		return ParameterName.values();
	}

	@Override
	public String getJobName() {
		return this.getClass().getName();
	}

	@Override
	public String getRenderedParameter(JobParameterConfiguration config) {		
		try {
			AbstractParameterView parameterView = getSparseParameterView(config, "org/bu/jenkins/active_choices/html/job-parameter/");
			
			applyCustomStateToParameterView(config, parameterView);
			
			return parameterView.render();
		} 
		catch (Exception e) {
			e.printStackTrace();
			return stackTraceToHTML(e);
		}
	}
	
	/**
	 * This is where we "decide", based on the value of other parameters, what a parameter should offer for choices
	 * and whether or not it should be enabled/visible at all. This is done by loading the view context with the 
	 * appropriate values/objects.
	 * @param config
	 * @param parameterView
	 */
	@SuppressWarnings("incomplete-switch")
	private void applyCustomStateToParameterView(JobParameterConfiguration config, AbstractParameterView parameterView) throws Exception {
		
		ParameterName parameter = ParameterName.valueOf(config.getParameterName());
		
		JobParameter jobParameter = new JobParameter(parameter, config.getParameterMap());
		if( ! jobParameter.otherParmBlank(ParameterName.STACK)) {
			parameterView.setContextVariable("stackSelected", true);
		}
		switch(parameter) {
			case STACK:
				StackList stackList = new StackList(credentials);
				parameterView.setContextVariable("stacks", stackList.getKualiApplicationStacks());
				break;
			case STACK_ACTION:
				if( ! jobParameter.otherParmBlank(ParameterName.STACK)) {
					parameterView.setContextVariable("stackSelected", true);
				}
				break;
			case value:
				parameterView.setContextVariable("jobName", getJobName());
				break;
			default:
				if( ! jobParameter.otherParmSetWith(ParameterName.STACK_ACTION, "create")) {
					parameterView.setContextVariable("deactivate", true);
				}
				else {
					switch(parameter) {
						case LANDSCAPE:
							break;
						case STACK_TYPE:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "ecs");
								parameterView.setContextVariable("ecs_only", true);
							}
							break;
						case BASELINE:
							parameterView.setContextVariable("landscapes", new LandscapeList(credentials).getBaselineLandscapes());
							break;
						case AUTHENTICATION:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "shibboleth");
								parameterView.setContextVariable("deactivate_cor_main", true);
							}
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2") || 
									jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "sb")) {
								parameterView.setContextVariable("ParameterValue", "cor-main");
								parameterView.setContextVariable("deactivate_shibboleth", true);
							}
							break;
						case DNS:							
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "route53");
								parameterView.setContextVariable("deactivate_none", true);
							}							
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2")) {
								parameterView.setContextVariable("ParameterValue", "none");
								parameterView.setContextVariable("deactivate_route53", true);
							}
							else if(jobParameter.otherParmSetWith(ParameterName.AUTHENTICATION, "shibboleth")) {
								parameterView.setContextVariable("ParameterValue", "route53");
								if( ! jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "sb")) {
									parameterView.setContextVariable("deactivate_none", true);
								}
							}							
							break;
						case WAF:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_waf", true);
								parameterView.setContextVariable("ParameterValue", "enabled");
							}
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2")) {
								parameterView.setContextVariable("deactivate_waf", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}
							break;
						case ALB:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_alb", true);
								parameterView.setContextVariable("ParameterValue", "enabled");
							}
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2")) {
								parameterView.setContextVariable("deactivate_alb", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}
							else if(jobParameter.otherParmSetWith(ParameterName.WAF, "enabled")) {
								parameterView.setContextVariable("deactivate_alb", true);
								parameterView.setContextVariable("ParameterValue", "enabled");
							}
							break;
						case RDS_CLONE_LANDSCAPE:							
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_landscape", true);
								parameterView.setContextVariable("landscapes", new HashMap<String, String>());
								parameterView.setContextVariable("ParameterValue", "none");
							}
							else {
								LandscapeList landscapeList = new LandscapeList(credentials);
								parameterView.setContextVariable("landscapes", landscapeList.getDeployedKualiRdsInstancesByLandscape());
								String urlEncodedValue = config.getParameterMap().get(parameter.name());
								if(urlEncodedValue != null) {
									String urlDecodedValue = URLDecoder.decode(urlEncodedValue, Charset.defaultCharset());
									parameterView.setContextVariable("ParameterValue", urlDecodedValue);
								}
							}
							break;
						case RDS_SNAPSHOT:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_snapshot", true);
							}
							else if(jobParameter.otherParmBlank(ParameterName.RDS_CLONE_LANDSCAPE) || 
									jobParameter.otherParmSetWith(ParameterName.RDS_CLONE_LANDSCAPE, "none")) {
								parameterView.setContextVariable("deactivate_snapshot", true);
							}
							else {
								String urlEncodedRdsArn = jobParameter.getOtherParmValue(ParameterName.RDS_CLONE_LANDSCAPE);
								if(urlEncodedRdsArn != null) {
									String urlDecodedValue = URLDecoder.decode(urlEncodedRdsArn, Charset.defaultCharset());
									RdsSnapshot snapshots = new RdsSnapshot(credentials).setRdsInstanceARN(urlDecodedValue);
									parameterView.setContextVariable("manualSnapshots", snapshots.getManuallyCreated());
									parameterView.setContextVariable("automatedSnapshots", snapshots.getAutomaticallyCreated());								
								}
								String urlEncodedSnapshotArn = config.getParameterMap().get(parameter.name());
								if(urlEncodedSnapshotArn != null) {
									String urlDecodedSnapshotArn = URLDecoder.decode(urlEncodedSnapshotArn, Charset.defaultCharset());
									parameterView.setContextVariable("ParameterValue", urlDecodedSnapshotArn);
								}
							}
							break;
						case MONGO:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_mongo", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}							
							break;
					}					
				}
		}
		
	}

	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(args);
		AbstractJob job = new StackCreateDelete(new AWSCredentials(namedArgs));
		
		if(namedArgs.has("parameter-name")) {
			if(ParameterName.valueOf(namedArgs.get("parameter-name")) == null) {
				System.out.println("No such parameter name!");
				return;
			}
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					JobParameterConfiguration config = 
							JobParameterConfiguration.forTestFragmentInstance(namedArgs.get("ParameterName"))
							.setParameterMap(parameters);
					return job.getRenderedParameter(config);
				}}.visitWithBrowser(false);
		}
		else {
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					return job.getRenderedJob(parameters, true);
				}}.visitWithBrowser(true);			
		}
	}
}
