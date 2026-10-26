function [resultados, resumo] = e10_coletar_inversao_prioridade(porta, pastaResultados, mostrarGrafico)
%E10_COLETAR_INVERSAO_PRIORIDADE Compara mutex e semaforo binario.

diretorioScript = fileparts(mfilename('fullpath'));
raizBancada = fileparts(diretorioScript);
assert(isfolder(fullfile(raizBancada, 'firmware', 'str')), ...
    'Estrutura do repositorio invalida: firmware/str nao encontrado.');

if nargin < 1 || strlength(string(porta)) == 0
    porta = "COM3";
end
if nargin < 2 || strlength(string(pastaResultados)) == 0
    pastaResultados = fullfile(raizBancada, 'resultados', 'reproduzidos', 'e10');
end
if nargin < 3 || isempty(mostrarGrafico)
    mostrarGrafico = true;
end

porta = string(porta);
pastaResultados = string(pastaResultados);
assert(islogical(mostrarGrafico) && isscalar(mostrarGrafico));
if ~isfolder(pastaResultados)
    mkdir(pastaResultados);
end

portasDisponiveis = string(serialportlist("available"));
assert(any(strcmpi(portasDisponiveis, porta)), ...
    'A porta %s nao esta disponivel. Feche o monitor serial.', porta);

sp = serialport(porta,115200,'Timeout',3);
cleanup = onCleanup(@() limparSerial(sp));
configureTerminator(sp,"LF");
pause(1.0);
flush(sp);

writeline(sp,"PING");
pong = aguardarPrefixo(sp,"ACK,PONG,E10_PRIORITY_INVERSION",5);
assert(pong == "ACK,PONG,E10_PRIORITY_INVERSION", ...
    'Firmware conectado nao e o E10: %s',pong);
writeline(sp,"START");
ack = aguardarPrefixo(sp,"ACK,START,E10",5);
assert(ack == "ACK,START,E10",'E10 nao iniciou: %s',ack);

fprintf('\nE10: comparando mutex e semaforo binario na %s.\n',porta);
fprintf('A fonte de 12 V deve permanecer desligada.\n\n');

cenario = strings(0,1);
repeticao = zeros(0,1);
esperaAltaUs = zeros(0,1);
janelaBaixaUs = zeros(0,1);
janelaMediaUs = zeros(0,1);
prioridadeEfetivaBaixa = zeros(0,1);
motivoFim = "";
inicio = tic;
while toc(inicio) < 60 && strlength(motivoFim) == 0
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    linha = strtrim(readline(sp));
    if startsWith(linha,"RESULT,E10,")
        partes = split(linha,',');
        assert(numel(partes) == 8,'Linha RESULT E10 invalida: %s',linha);
        cenario(end+1,1) = partes(3); %#ok<AGROW>
        repeticao(end+1,1) = str2double(partes(4)); %#ok<AGROW>
        esperaAltaUs(end+1,1) = str2double(partes(5)); %#ok<AGROW>
        janelaBaixaUs(end+1,1) = str2double(partes(6)); %#ok<AGROW>
        janelaMediaUs(end+1,1) = str2double(partes(7)); %#ok<AGROW>
        prioridadeEfetivaBaixa(end+1,1) = str2double(partes(8)); %#ok<AGROW>
    elseif startsWith(linha,"EVENT,END,")
        partes = split(linha,',');
        motivoFim = partes(3);
    elseif startsWith(linha,"ERRO,")
        error('Firmware E10 reportou erro: %s',linha);
    end
end

assert(motivoFim == "FIM_NORMAL", ...
    'E10 nao terminou normalmente. Motivo: %s',motivoFim);
resultados = table(cenario,repeticao,esperaAltaUs,janelaBaixaUs, ...
    janelaMediaUs,prioridadeEfetivaBaixa, ...
    'VariableNames',{'cenario','repeticao','espera_alta_us', ...
    'janela_baixa_us','janela_media_us','prioridade_efetiva_baixa'});

esperados = ["MUTEX_BASELINE";"MUTEX_HERANCA";"BINARIO_INVERSAO"];
assert(height(resultados) == 90,'Esperados 90 resultados; recebidos %d.', ...
    height(resultados));
valoresNumericos = resultados{:,2:end};
assert(all(isfinite(valoresNumericos(:))) && ...
    all(resultados.espera_alta_us > 0));

resumo = resumir(resultados,esperados);
validar(resultados,resumo,esperados);

instante = string(datetime('now','Format','yyyy-MM-dd_HHmmss'));
base = fullfile(pastaResultados,instante + "_E10_r01");
writetable(resultados,base + "_resultados.csv");
writetable(resumo,base + "_metricas.csv");

fid = fopen(base + "_integridade.txt",'w');
assert(fid >= 0,'Nao foi possivel criar integridade E10.');
fecharArquivo = onCleanup(@() fclose(fid));
fprintf(fid,'motivo_fim=%s\n',motivoFim);
fprintf(fid,'resultados=%d\n',height(resultados));
fprintf(fid,'repeticoes_por_cenario=30\n');
clear fecharArquivo

plotar(resultados,resumo,base + "_inversao_prioridade.png",mostrarGrafico);
disp(resumo);
fprintf('\nE10 APROVADO: heranca de prioridade limitou a inversao.\n');
fprintf('Resultados: %s\n',base + "_resultados.csv");
fprintf('Metricas:   %s\n',base + "_metricas.csv");
end

function resumo = resumir(resultados,cenarios)
n = numel(cenarios);
repeticoes = zeros(n,1);
mediaUs = zeros(n,1);
medianaUs = zeros(n,1);
p95Us = zeros(n,1);
p99Us = zeros(n,1);
maxUs = zeros(n,1);
prioridadeBaixa = zeros(n,1);
janelaMedia = zeros(n,1);
for k = 1:n
    selecao = resultados.cenario == cenarios(k);
    x = resultados.espera_alta_us(selecao);
    repeticoes(k) = numel(x);
    mediaUs(k) = mean(x);
    medianaUs(k) = median(x);
    p95Us(k) = percentil(x,95);
    p99Us(k) = percentil(x,99);
    maxUs(k) = max(x);
    prioridadeBaixa(k) = median(resultados.prioridade_efetiva_baixa(selecao));
    janelaMedia(k) = median(resultados.janela_media_us(selecao));
end
resumo = table(cenarios,repeticoes,mediaUs,medianaUs,p95Us,p99Us,maxUs, ...
    prioridadeBaixa,janelaMedia,'VariableNames', ...
    {'cenario','repeticoes','espera_media_us','espera_mediana_us', ...
    'espera_p95_us','espera_p99_us','espera_max_us', ...
    'prioridade_efetiva_baixa','janela_media_mediana_us'});
end

function validar(resultados,resumo,cenarios)
for k = 1:numel(cenarios)
    x = sort(resultados.repeticao(resultados.cenario == cenarios(k)));
    assert(isequal(x,(1:30)'),'Repeticoes inconsistentes em %s.',cenarios(k));
end
assert(all(resumo.repeticoes == 30));
assert(resumo.prioridade_efetiva_baixa(1) == 6 && ...
    resumo.prioridade_efetiva_baixa(2) == 6, ...
    'O mutex nao elevou a tarefa baixa para a prioridade da tarefa alta.');
assert(resumo.prioridade_efetiva_baixa(3) == 2, ...
    'O semaforo binario alterou inesperadamente a prioridade da tarefa baixa.');
assert(resumo.espera_mediana_us(3) > resumo.espera_mediana_us(2) + 30000, ...
    'A inversao com semaforo nao produziu o atraso minimo esperado.');
assert(resumo.espera_mediana_us(2) <= resumo.espera_mediana_us(1)*1.25 + 2000, ...
    'A tarefa media interferiu excessivamente apesar da heranca.');
end

function plotar(resultados,resumo,arquivo,mostrar)
visibilidade = 'off';
if mostrar
    visibilidade = 'on';
end
fig = figure('Color','w','Visible',visibilidade, ...
    'Name','E10 - inversao de prioridade');
layout = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');
rotulos = ["Mutex baseline","Mutex com herança","Semáforo binário"];
ax1 = nexttile(layout);
grupos = categorical(resultados.cenario,unique(resultados.cenario,'stable'),rotulos);
swarmchart(ax1,grupos,resultados.espera_alta_us/1000,24,'filled', ...
    'MarkerFaceAlpha',0.65,'MarkerEdgeAlpha',0.65);
grid(ax1,'on');
ylabel(ax1,'Espera da tarefa alta (ms)');
title(ax1,'30 medições individuais');
xtickangle(ax1,20);
ax1.TickLabelInterpreter = 'none';

ax2 = nexttile(layout);
bar(ax2,[resumo.espera_mediana_us resumo.espera_p95_us resumo.espera_max_us]/1000);
grid(ax2,'on');
ylabel(ax2,'Espera da tarefa alta (ms)');
title(ax2,'Mediana, P95 e máximo');
xticks(ax2,1:height(resumo));
xticklabels(ax2,rotulos);
xtickangle(ax2,20);
ax2.TickLabelInterpreter = 'none';
legend(ax2,{'Mediana','P95','Máximo'},'Location','northwest');
sgtitle(layout,'E10 — mutex com herança versus semáforo binário');
exportgraphics(fig,arquivo,'Resolution',180);
if ~mostrar
    close(fig);
end
end

function linha = aguardarPrefixo(sp,prefixo,timeoutS)
inicio = tic;
while toc(inicio) < timeoutS
    if sp.NumBytesAvailable == 0
        pause(0.01);
        continue;
    end
    candidata = strtrim(readline(sp));
    if startsWith(candidata,prefixo)
        linha = candidata;
        return;
    end
end
error('Timeout aguardando %s.',prefixo);
end

function valor = percentil(x,p)
x = sort(x(:));
assert(~isempty(x));
posicao = 1 + (numel(x)-1)*p/100;
inferior = floor(posicao);
superior = ceil(posicao);
if inferior == superior
    valor = x(inferior);
else
    valor = x(inferior) + (posicao-inferior)*(x(superior)-x(inferior));
end
end

function limparSerial(sp)
try
    flush(sp);
catch
end
end
