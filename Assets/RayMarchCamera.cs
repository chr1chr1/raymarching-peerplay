using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[RequireComponent(typeof(Camera))]
[ExecuteInEditMode]
public class RayMarchCamera : SceneViewFilter
{
    [SerializeField]
    public Shader _shader;
    public Material _raymarchMat;
    public Camera _cam;
    
    [Header("Setup")]
    public float _maxDistance;
    [Range(1,300)]
    public int _maxIterations;

    [Header("Directional Light")]
    public Transform _lightDir;
    public Color _lightCol;
    public float _lightIntensity;

    [Header("Shadow")] 
    [Range(0,4)] public float _shadowIntensity;
    public Vector2 _shadowDist;
    [Range(1, 128)] public float _shadowPenumbra;

    [Header("Ambient Occlusion")] 
    [Range(0.01f, 10.0f)]    
    public float _aoStepSize;
    [Range(1,5)]    
    public int _aoIterations;
    [Range(0f, 1f)]
    public float _aoIntensity;
    
    
    [Header("Signed Distance Field")]
    public Color _mainColor;
    public Vector4 _sphere1, _box1;
    public float _box1round;
    public float _boxSphereSmooth;
    public Vector4 _sphere2;
    public float _sphereIntersectSmooth;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {

        if (!_raymarchMat && _shader)
        {
            _raymarchMat = new Material(_shader);
            _raymarchMat.hideFlags = HideFlags.HideAndDontSave;
        }

        if (!_cam)
        {
            _cam = GetComponent<Camera>();
        }

        if (!_raymarchMat)
        {
            Graphics.Blit(source, destination);
            return;
        }

        _raymarchMat.SetMatrix("_CamFrustum", CamFrustum(_cam));
        _raymarchMat.SetMatrix("_CamToWorld", _cam.cameraToWorldMatrix);
        _raymarchMat.SetVector("_CamWorldSpace", _cam.transform.position);
        _raymarchMat.SetFloat("_maxDistance", _maxDistance);
        _raymarchMat.SetFloat("_maxIterations", _maxIterations);
        
        _raymarchMat.SetFloat("_box1round", _box1round);
        _raymarchMat.SetFloat("_boxSphereSmooth", _boxSphereSmooth);
        _raymarchMat.SetFloat("_sphereIntersectSmooth", _sphereIntersectSmooth);
        _raymarchMat.SetVector("_sphere1", _sphere1);
        _raymarchMat.SetVector("_sphere2", _sphere2);
        _raymarchMat.SetVector("_box1", _box1);

        _raymarchMat.SetVector("_lightDir", _lightDir ? _lightDir.forward : _lightDir.up);
        _raymarchMat.SetColor("_lightCol", _lightCol);
        _raymarchMat.SetFloat("_lightIntensity", _lightIntensity);
        _raymarchMat.SetFloat("_shadowIntensity", _shadowIntensity);
        _raymarchMat.SetFloat("_shadowPenumbra", _shadowPenumbra);
        _raymarchMat.SetVector("_shadowDist", _shadowDist);
        _raymarchMat.SetColor("_mainColor", _mainColor);
        
        _raymarchMat.SetFloat("_aoStepSize", _aoStepSize);
        _raymarchMat.SetFloat("_aoIntensity", _aoIntensity);
        _raymarchMat.SetInt("_aoIterations", _aoIterations);
        

        RenderTexture.active = destination;
        _raymarchMat.SetTexture("_MainTex", source);
        GL.PushMatrix();
        GL.LoadOrtho();
        _raymarchMat.SetPass(0);
        GL.Begin(GL.QUADS);

        // BL
        GL.MultiTexCoord2(0, 0.0f, 0.0f);
        GL.Vertex3(0.0f, 0.0f, 3.0f);
        // BR
        GL.MultiTexCoord2(0, 1.0f, 0.0f);
        GL.Vertex3(1.0f, 0.0f, 2.0f);
        // TR
        GL.MultiTexCoord2(0, 1.0f, 1.0f);
        GL.Vertex3(1.0f, 1.0f, 1.0f);
        // TL
        GL.MultiTexCoord2(0, 0.0f, 1.0f);
        GL.Vertex3(0.0f, 1.0f, 0.0f);

        GL.End();
        GL.PopMatrix();

    }

    private Matrix4x4 CamFrustum(Camera cam)
    {
        Matrix4x4 frustum = Matrix4x4.identity;
        float fov = Mathf.Tan((cam.fieldOfView * 0.5f) * Mathf.Deg2Rad);

        Vector3 goUp = Vector3.up * fov;
        Vector3 goRight = Vector3.right * fov * cam.aspect;

        Vector3 TL = (-Vector3.forward - goRight + goUp);
        Vector3 TR = (-Vector3.forward + goRight + goUp);
        Vector3 BR = (-Vector3.forward + goRight - goUp);
        Vector3 BL = (-Vector3.forward - goRight - goUp);

        frustum.SetRow(0, TL);
        frustum.SetRow(1, TR);
        frustum.SetRow(2, BR);
        frustum.SetRow(3, BL);

        return frustum;
    }
}